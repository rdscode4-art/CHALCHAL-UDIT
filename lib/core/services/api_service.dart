import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../constants/app_constants.dart';
import './ride_status.dart';
import './session_service.dart';

/// Central API service — all calls to the ChalChalGaadi backend go here.
///
/// Base URL is controlled by [AppConstants.apiBaseUrl].
class ApiService {
  static String get baseUrl => AppConstants.apiBaseUrl;

  static final http.Client _client = http.Client();

  // ── Helpers ────────────────────────────────────────────────────────────────
  static Map<String, String> get _jsonHeaders => {
    'Content-Type': 'application/json',
  };

  /// Get JSON headers with authentication token if available
  static Future<Map<String, String>> _authHeaders() async {
    final token = await SessionService.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static String? _messageFromBody(Map<String, dynamic> body) {
    final message = body['message'];
    if (message is String && message.isNotEmpty) return message;

    final error = body['error'];
    if (error is String && error.isNotEmpty) return error;
    if (error != null) return error.toString();

    return null;
  }

  /// Triggered globally when a 401 with a session-expired error is intercepted.
  static void Function()? onSessionExpired;

  static ApiResponse _parse(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      
      // Check for 401 Global Interceptor
      if (res.statusCode == 401) {
        if (decoded is Map<String, dynamic>) {
          final message = _messageFromBody(decoded)?.toLowerCase() ?? '';
          final isSessionExpired = message.contains('session') || 
                                   message.contains('invalid') || 
                                   message.contains('expired');
          if (isSessionExpired) {
            debugPrint('EVENT: session_forced_logout_401');
            onSessionExpired?.call();
          }
        }
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (decoded is Map<String, dynamic>) {
          return ApiResponse.success(decoded);
        } else if (decoded is List<dynamic>) {
          return ApiResponse.success({'data': decoded, 'rides': decoded});
        }
      }
      if (decoded is Map<String, dynamic>) {
        final message =
            _messageFromBody(decoded) ?? 'Server error ${res.statusCode}';
        return ApiResponse.error(message, statusCode: res.statusCode);
      }
      return ApiResponse.error(
        'Unexpected response from server.',
        statusCode: res.statusCode,
      );
    } catch (_) {
      return ApiResponse.error(
        'Unexpected response from server.',
        statusCode: res.statusCode,
      );
    }
  }

  static Future<void> _attachFileIfExists(
    http.MultipartRequest request,
    String field,
    String filePath,
  ) async {
    if (filePath.trim().isEmpty) return;
    // Try File path first (desktop/iOS)
    final file = File(filePath);
    if (await file.exists()) {
      request.files.add(await http.MultipartFile.fromPath(field, filePath));
      return;
    }
    // On Android, file_selector returns content:// URIs that File() can't open.
    // Fall through silently — caller should use _attachXFileIfExists instead.
    debugPrint(
      '⚠️ [UPLOAD] File not found via path (may be content URI): $filePath',
    );
  }

  /// Attach an [XFile] to a multipart request using readAsBytes() —
  /// works correctly with Android content:// URIs from file_selector.
  static Future<void> _attachXFileIfExists(
    http.MultipartRequest request,
    String field,
    dynamic xfile, // XFile? — typed as dynamic to avoid import in api_service
  ) async {
    if (xfile == null) return;
    try {
      // XFile has readAsBytes() and name — use dynamic access
      final bytes = await (xfile as dynamic).readAsBytes() as List<int>;
      if (bytes.isEmpty) return;
      final name = (xfile as dynamic).name as String? ?? field;
      final mimeType = name.toLowerCase().endsWith('.pdf')
          ? 'application/pdf'
          : 'image/jpeg';
      request.files.add(
        http.MultipartFile.fromBytes(
          field,
          bytes,
          filename: name,
          contentType: MediaType.parse(mimeType),
        ),
      );
      debugPrint('✅ [UPLOAD] Attached $field: $name (${bytes.length} bytes)');
    } catch (e) {
      debugPrint('⚠️ [UPLOAD] Failed to attach $field: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHAT
  // ══════════════════════════════════════════════════════════════════════════

  /// POST /api/chat/send — send a chat message during a ride.
  ///
  /// [rideId]     The active ride ID.
  /// [senderId]   The user or driver ID sending the message.
  /// [senderModel] 'user' or 'driver'.
  /// [message]    The text message content.
  static Future<ApiResponse> sendChatMessage({
    required String rideId,
    required String senderId,
    required String senderModel, // 'user' or 'driver'
    required String message,
    String? receiverId, // required by backend before driver is assigned
    String? receiverModel, // 'user' or 'driver' — opposite of senderModel
  }) async {
    try {
      final body = <String, dynamic>{
        'rideId': rideId,
        'senderId': senderId,
        'senderModel': senderModel,
        'message': message,
      };
      // Backend requires receiverId when ride is not yet assigned to a driver.
      if (receiverId != null && receiverId.isNotEmpty) {
        body['receiverId'] = receiverId;
        body['receiverModel'] =
            receiverModel ?? (senderModel == 'user' ? 'driver' : 'user');
      }
      final res = await _client.post(
        Uri.parse('$baseUrl/api/chat/send'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      debugPrint('📡 [API] POST /api/chat/send: ${res.statusCode}');
      debugPrint('📡 [API] Chat payload: ${jsonEncode(body)}');
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Send message failed: $e');
    }
  }

  /// GET /api/chat/:rideId — fetch full chat history for a ride.
  static Future<ApiResponse> getChatHistory(String rideId) async {
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl/api/chat/$rideId'),
        headers: _jsonHeaders,
      );
      debugPrint('📡 [API] GET /api/chat/$rideId: ${res.statusCode}');
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Fetch chat history failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // USER
  // ══════════════════════════════════════════════════════════════════════════

  /// POST /users  — create a new user account.
  ///
  /// [name]  Full name of the user.
  /// [phone] Phone number with country code, e.g. "+919876543210".
  ///
  /// Example curl:
  /// ```bash
  /// curl -X POST http://localhost:3000/users \
  ///   -H "Content-Type: application/json" \
  ///   -d '{"name": "Amit Sharma", "phone": "+919876543210"}'
  /// ```
  static Future<ApiResponse> userSignUp({
    required String name,
    required String phone,
  }) async {
    try {
      final res = await _client.post(
        Uri.parse('$baseUrl/users'),
        headers: _jsonHeaders,
        body: jsonEncode({'name': name, 'phone': phone}),
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('User sign-up failed: $e');
    }
  }

  // ── OTP-based authentication (new unified flow) ───────────────────────────

  /// POST /api/auth/send-otp
  /// Sends OTP via Firebase push notification.
  /// [role] must be "user" or "driver".
  static Future<ApiResponse> sendOtp({
    required String phone,
    required String role,
    String? fcmToken,
  }) async {
    try {
      final body = <String, dynamic>{'phone': phone, 'role': role};
      if (fcmToken != null && fcmToken.isNotEmpty) {
        body['fcmToken'] = fcmToken;
      }
      final res = await _client.post(
        Uri.parse('$baseUrl/api/auth/send-otp'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      debugPrint('📡 [API] POST /api/auth/send-otp: ${res.statusCode}');
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Send OTP failed: $e');
    }
  }

  /// POST /api/auth/verify-otp
  /// Verifies OTP. Returns:
  ///   - isNewUser: false → full profile + JWT in response → go to Home
  ///   - isNewUser: true  → need to call completeUserProfile / completeDriverProfile
  static Future<ApiResponse> verifyOtp({
    required String phone,
    required String otp,
    required String role,
    String? fcmToken,
    String? deviceInfo,
  }) async {
    try {
      final body = {'phone': phone, 'otp': otp, 'role': role};
      if (fcmToken != null) body['fcmToken'] = fcmToken;
      if (deviceInfo != null) body['deviceInfo'] = deviceInfo;

      final res = await _client.post(
        Uri.parse('$baseUrl/api/auth/verify-otp'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      debugPrint('📡 [API] POST /api/auth/verify-otp: ${res.statusCode}');
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Verify OTP failed: $e');
    }
  }

  /// POST /api/users/complete-profile
  /// Called only when verifyOtp returns isNewUser: true for a user.
  static Future<ApiResponse> completeUserProfile({
    required String name,
    required String phone,
    String? fcmToken,
  }) async {
    try {
      final body = <String, dynamic>{'name': name, 'phone': phone};
      if (fcmToken != null && fcmToken.isNotEmpty) {
        body['fcmToken'] = fcmToken;
      }
      final res = await _client.post(
        Uri.parse('$baseUrl/api/users/complete-profile'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      debugPrint(
        '📡 [API] POST /api/users/complete-profile: ${res.statusCode}',
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Complete user profile failed: $e');
    }
  }

  /// POST /api/drivers/complete-profile  (multipart/form-data)
  /// Called only when verifyOtp returns isNewUser: true for a driver.
  static Future<ApiResponse> completeDriverProfile({
    required String name,
    required String phone,
    required String vehicleType,
    required String vehicleNumber,
    double lat = 0.0,
    double lng = 0.0,
    String? fcmToken,
    String? deviceInfo,
    String profilePhotoPath = '',
    String drivingLicenseFrontPath = '',
    String aadharFrontPath = '',
    String aadharBackPath = '',
    String rcPhotoPath = '',
    String insurancePhotoPath = '',
    String pucPhotoPath = '',
    // Document numbers (text fields required by backend)
    String drivingLicenseNumber = '',
    String aadharNumber = '',
    // XFile objects for Android content URI support
    dynamic profilePhotoXFile,
    dynamic drivingLicenseFrontXFile,
    dynamic aadharFrontXFile,
    dynamic aadharBackXFile,
    dynamic rcPhotoXFile,
    dynamic insurancePhotoXFile,
    dynamic pucPhotoXFile,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/drivers/complete-profile');
      final request = http.MultipartRequest('POST', uri);

      request.fields['name'] = name;
      request.fields['phone'] = phone;
      request.fields['vehicleType'] = vehicleType;
      request.fields['vehicleNumber'] = vehicleNumber;
      request.fields['lat'] = lat.toString();
      request.fields['lng'] = lng.toString();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        request.fields['fcmToken'] = fcmToken;
      }
      if (deviceInfo != null && deviceInfo.isNotEmpty) {
        request.fields['deviceInfo'] = deviceInfo;
      }
      // Send document numbers as text fields
      if (drivingLicenseNumber.isNotEmpty) {
        request.fields['drivingLicenseNumber'] = drivingLicenseNumber;
      }
      if (aadharNumber.isNotEmpty) {
        request.fields['aadharNumber'] = aadharNumber;
      }

      // Use XFile.readAsBytes() when available (handles Android content URIs)
      // Fall back to File path for desktop/iOS
      Future<void> attach(String field, String path, dynamic xfile) async {
        if (xfile != null) {
          await _attachXFileIfExists(request, field, xfile);
        } else {
          await _attachFileIfExists(request, field, path);
        }
      }

      await attach('profilePhoto', profilePhotoPath, profilePhotoXFile);
      await attach(
        'drivingLicensePhotoFront',
        drivingLicenseFrontPath,
        drivingLicenseFrontXFile,
      );
      await attach('aadharFrontPhoto', aadharFrontPath, aadharFrontXFile);
      await attach('aadharBackPhoto', aadharBackPath, aadharBackXFile);
      await attach('rcPhoto', rcPhotoPath, rcPhotoXFile);
      await attach('insurancePhoto', insurancePhotoPath, insurancePhotoXFile);
      await attach('pucPhoto', pucPhotoPath, pucPhotoXFile);

      debugPrint(
        '📡 [API] POST /api/drivers/complete-profile — ${request.files.length} files attached',
      );
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      debugPrint(
        '📡 [API] POST /api/drivers/complete-profile: ${res.statusCode}',
      );
      debugPrint('📡 [API] Response: ${res.body}');
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Complete driver profile failed: $e');
    }
  }

  /// PUT /drivers/:id — Update driver profile details and documents
  static Future<ApiResponse> updateDriverProfile({
    required String driverId,
    required String name,
    required String email,
    required String vehicleType,
    required String vehicleNumber,
    required String drivingLicenseNumber,
    required String aadharNumber,
    String? profilePhotoPath,
    String? drivingLicenseFrontPath,
    String? aadharFrontPath,
    String? aadharBackPath,
    String? rcPhotoPath,
    String? insurancePhotoPath,
    String? pucPhotoPath,
    dynamic profilePhotoXFile,
    dynamic drivingLicenseFrontXFile,
    dynamic aadharFrontXFile,
    dynamic aadharBackXFile,
    dynamic rcPhotoXFile,
    dynamic insurancePhotoXFile,
    dynamic pucPhotoXFile,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/drivers/$driverId');
      final request = http.MultipartRequest('PUT', uri);

      final token = await SessionService.getToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['name'] = name;
      request.fields['email'] = email;
      request.fields['vehicleType'] = vehicleType;
      request.fields['vehicleNumber'] = vehicleNumber;
      request.fields['drivingLicenseNumber'] = drivingLicenseNumber;
      request.fields['aadharNumber'] = aadharNumber;

      Future<void> attach(String field, String? path, dynamic xfile) async {
        if (xfile != null) {
          await _attachXFileIfExists(request, field, xfile);
        } else if (path != null && path.isNotEmpty) {
          await _attachFileIfExists(request, field, path);
        }
      }

      await attach('profilePhoto', profilePhotoPath, profilePhotoXFile);
      await attach('drivingLicensePhotoFront', drivingLicenseFrontPath, drivingLicenseFrontXFile);
      await attach('aadharFrontPhoto', aadharFrontPath, aadharFrontXFile);
      await attach('aadharBackPhoto', aadharBackPath, aadharBackXFile);
      await attach('rcPhoto', rcPhotoPath, rcPhotoXFile);
      await attach('insurancePhoto', insurancePhotoPath, insurancePhotoXFile);
      await attach('pucPhoto', pucPhotoPath, pucPhotoXFile);

      debugPrint('📡 [API] PUT /drivers/$driverId — ${request.files.length} files attached');
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      debugPrint('📡 [API] PUT /drivers/$driverId: ${res.statusCode}');
      debugPrint('📡 [API] Response: ${res.body}');
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Update driver profile failed: $e');
    }
  }

  // ── Legacy login methods (kept for fallback) ───────────────────────────────

  /// POST /users/login  — existing user login with phone only.
  static Future<ApiResponse> userLogin({required String phone}) async {
    try {
      final res = await _client.post(
        Uri.parse('$baseUrl/users/login'),
        headers: _jsonHeaders,
        body: jsonEncode({'phone': phone}),
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('User login failed: $e');
    }
  }

  /// PUT /api/users/:userId/fcm-token — upload user FCM token for push notifications.
  static Future<ApiResponse> updateUserFcmToken({
    required String userId,
    required String fcmToken,
  }) async {
    if (userId.isEmpty || fcmToken.isEmpty) {
      return ApiResponse.error('User ID or FCM token is missing.');
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final res = await _client.put(
        Uri.parse('$baseUrl/api/users/$encodedUserId/fcm-token'),
        headers: _jsonHeaders,
        body: jsonEncode({'fcmToken': fcmToken}),
      );
      debugPrint(
        '📡 [API] PUT /api/users/$userId/fcm-token: ${res.statusCode}',
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Update user FCM token failed: $e');
    }
  }

  /// GET /users/:userId — fetch user profile details.
  static Future<ApiResponse> getUserProfile(String userId) async {
    if (userId.startsWith('user_') ||
        userId == 'guest_user' ||
        userId.isEmpty) {
      final session = await SessionService.getSession();
      return ApiResponse.success({
        'id': userId,
        'name': session['name'] ?? 'Guest User',
        'phone': session['phone'] ?? '+919876543210',
        'email': session['email'] ?? 'guest@example.com',
      });
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final res = await _client.get(
        Uri.parse('$baseUrl/users/$encodedUserId'),
        headers: await _authHeaders(),
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Fetch user profile failed: $e');
    }
  }

  /// PATCH /users/:userId — update user profile details.
  static Future<ApiResponse> updateUserProfile({
    required String userId,
    String? name,
    String? email,
    String? phone,
  }) async {
    if (userId.startsWith('user_') ||
        userId == 'guest_user' ||
        userId.isEmpty) {
      return ApiResponse.success({
        'id': userId,
        'name': name ?? 'Guest User',
        'phone': phone ?? '+919876543210',
        'email': email ?? 'guest@example.com',
      });
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (email != null) body['email'] = email;
      if (phone != null) body['phone'] = phone;

      final res = await _client.patch(
        Uri.parse('$baseUrl/users/$encodedUserId'),
        headers: await _authHeaders(),
        body: jsonEncode(body),
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Update user profile failed: $e');
    }
  }

  /// PUT /api/users/:userId — upload user profile avatar.
  static Future<ApiResponse> uploadUserProfilePhoto({
    required String userId,
    required String name,
    required String filePath,
  }) async {
    if (userId.startsWith('user_') ||
        userId == 'guest_user' ||
        userId.isEmpty) {
      return ApiResponse.success({
        'id': userId,
        'name': name,
        'profilePhotoUrl': 'https://example.com/avatar.jpg',
      });
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final uri = Uri.parse('$baseUrl/api/users/$encodedUserId');
      final request = http.MultipartRequest('PUT', uri);

      final token = await SessionService.getToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['name'] = name;
      await _attachFileIfExists(request, 'profilePic', filePath);

      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Upload profile picture failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DRIVER
  // ══════════════════════════════════════════════════════════════════════════

  /// POST /drivers/:driverId/fcm-token — upload driver FCM token and device info for push notifications.
  static Future<ApiResponse> updateDriverFcmToken({
    required String driverId,
    required String fcmToken,
    String? deviceInfo,
  }) async {
    if (driverId.isEmpty || fcmToken.isEmpty) {
      return ApiResponse.error('Driver ID or FCM token is missing.');
    }
    try {
      final encodedDriverId = Uri.encodeComponent(driverId);
      final body = <String, dynamic>{'fcmToken': fcmToken};
      if (deviceInfo != null) body['deviceInfo'] = deviceInfo;

      final res = await _client.post(
        Uri.parse('$baseUrl/drivers/$encodedDriverId/fcm-token'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      debugPrint(
        '📡 [API] POST /drivers/$driverId/fcm-token: ${res.statusCode}',
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Update driver FCM token failed: $e');
    }
  }

  /// POST /drivers/logout — Explicitly log out the driver on the backend.
  static Future<ApiResponse> driverLogout({
    required String driverId,
  }) async {
    try {
      final res = await _client.post(
        Uri.parse('$baseUrl/drivers/logout'),
        headers: _jsonHeaders,
        body: jsonEncode({'driverId': driverId}),
      );
      debugPrint('📡 [API] POST /drivers/logout: ${res.statusCode}');
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Driver logout failed: $e');
    }
  }

  /// PUT /api/driver/:driverId — upload driver profile photo (multipart).
  /// Form fields: name, profilePhoto (file)
  static Future<ApiResponse> uploadDriverProfilePhoto({
    required String driverId,
    required String name,
    required String filePath,
  }) async {
    if (driverId.isEmpty) {
      return ApiResponse.error('Driver ID is missing.');
    }
    try {
      final encodedId = Uri.encodeComponent(driverId);
      final uri = Uri.parse('$baseUrl/api/driver/$encodedId');
      final request = http.MultipartRequest('PUT', uri);

      final token = await SessionService.getToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.headers['Accept'] = 'application/json';

      request.fields['name'] = name;
      await _attachFileIfExists(request, 'profilePhoto', filePath);

      debugPrint(
        '📡 [API] uploadDriverProfilePhoto → PUT /api/driver/$driverId',
      );
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      debugPrint(
        '📡 [API] uploadDriverProfilePhoto response: ${res.statusCode} ${res.body}',
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Upload profile photo failed: $e');
    }
  }

  /// POST /drivers/signup — register a new driver (multipart, includes file uploads).
  static Future<ApiResponse> driverSignUp({
    required String name,
    required String phone,
    required String email,
    required String driverVerificationDetails,
    required String drivingLicenseNumber,
    required String aadharNumber,
    required String vehicleType,
    required String vehicleNumber,
    required double lat,
    required double lng,
    required String profilePicPath,
    required String licensePicPath,
    required String aadharFrontPicPath,
    required String aadharBackPicPath,
    required String rcPicPath,
    required String insurancePicPath,
    required String pucPicPath,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/drivers/signup');
      final request = http.MultipartRequest('POST', uri)
        ..fields['name'] = name
        ..fields['phone'] = phone
        ..fields['email'] = email
        ..fields['driverVerificationDetails'] = driverVerificationDetails
        ..fields['drivingLicenseNumber'] = drivingLicenseNumber
        ..fields['aadharNumber'] = aadharNumber
        ..fields['vehicleType'] = vehicleType
        ..fields['vehicleNumber'] = vehicleNumber
        ..fields['lat'] = lat.toString()
        ..fields['lng'] = lng.toString();

      await _attachFileIfExists(request, 'profilePhoto', profilePicPath);
      await _attachFileIfExists(
        request,
        'drivingLicensePhotoFront',
        licensePicPath,
      );
      await _attachFileIfExists(
        request,
        'aadharFrontPhoto',
        aadharFrontPicPath,
      );
      await _attachFileIfExists(request, 'aadharBackPhoto', aadharBackPicPath);
      await _attachFileIfExists(request, 'rcPhoto', rcPicPath);
      await _attachFileIfExists(request, 'insurancePhoto', insurancePicPath);
      await _attachFileIfExists(request, 'pucPhoto', pucPicPath);

      // ignore: avoid_print
      print('Driver SignUp Request to: $uri');
      // ignore: avoid_print
      print('Driver SignUp Fields: ${request.fields}');
      // ignore: avoid_print
      print(
        'Driver SignUp File Keys: ${request.files.map((f) => f.field).toList()}',
      );

      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);

      // ignore: avoid_print
      print('Driver SignUp Response Status: ${res.statusCode}');
      // ignore: avoid_print
      print('Driver SignUp Response Body: ${res.body}');

      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Driver sign-up failed: $e');
    }
  }

  /// POST /drivers/login  — driver login with phone + vehicle number.
  static Future<ApiResponse> driverLogin({
    required String phone,
    required String vehicleNumber,
    String? fcmToken,
    String? deviceInfo,
  }) async {
    try {
      // ignore: avoid_print
      print(
        'Driver Login request fields: phone=$phone, vehicleNumber=$vehicleNumber, fcmToken=$fcmToken, deviceInfo=$deviceInfo',
      );
      final body = {
        'phone': phone,
        'vehicleNumber': vehicleNumber,
      };
      if (fcmToken != null) body['fcmToken'] = fcmToken;
      if (deviceInfo != null) body['deviceInfo'] = deviceInfo;

      final res = await _client.post(
        Uri.parse('$baseUrl/drivers/login'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      // ignore: avoid_print
      print('Driver Login response status: ${res.statusCode}');
      // ignore: avoid_print
      print('Driver Login response body: ${res.body}');
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Driver login failed: $e');
    }
  }

  /// POST /drivers/status  — update driver online/offline status.
  static Future<ApiResponse> updateDriverStatus({
    required String driverId,
    String? status,
    bool? available,
    double? lat,
    double? lng,
  }) async {
    try {
      final body = <String, dynamic>{'driverId': driverId};
      if (status != null) body['status'] = status;
      if (available != null) {
        body['available'] = available;
        body['isOnline'] = available;
      }
      if (lat != null) {
        body['lat'] = lat;
        body['latitude'] = lat;
        body['currentLat'] = lat;
      }
      if (lng != null) {
        body['lng'] = lng;
        body['longitude'] = lng;
        body['currentLng'] = lng;
      }
      final headers = await _authHeaders();
      debugPrint('📡 [API] updateDriverStatus request: $body');
      final res = await _client.post(
        Uri.parse('$baseUrl/drivers/status'),
        headers: headers,
        body: jsonEncode(body),
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to update driver status: $e');
    }
  }

  /// PUT /drivers/:id/location - Update driver location ONLY (no status change)
  static Future<ApiResponse> updateDriverLocationOnly({
    required String driverId,
    required double lat,
    required double lng,
  }) async {
    try {
      final body = {
        'lat': lat,
        'lng': lng,
        'latitude': lat,
        'longitude': lng,
      };
      final headers = await _authHeaders();
      debugPrint('📡 [API] updateDriverLocationOnly Initiated: $body');
      final res = await _client.put(
        Uri.parse('$baseUrl/drivers/$driverId/location'),
        headers: headers,
        body: jsonEncode(body),
      );
      final parsedRes = _parse(res);
      if (parsedRes.success) {
        debugPrint('✅ [API] updateDriverLocationOnly SUCCESS');
      } else {
        debugPrint('❌ [API] updateDriverLocationOnly FAILED: ${parsedRes.errorMessage}');
      }
      return parsedRes;
    } on SocketException {
      debugPrint('❌ [API] updateDriverLocationOnly FAILED: No internet connection');
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      debugPrint('❌ [API] updateDriverLocationOnly ERROR: $e');
      return ApiResponse.error('Failed to update driver location: $e');
    }
  }

  /// GET /drivers/nearby?lat=&lng=  — get nearest drivers to a coordinate.
  ///
  /// Returns a list of driver objects in [ApiResponse.data]['drivers'].
  static Future<ApiResponse> getNearbyDrivers({
    required double lat,
    required double lng,
    String? driverId,
  }) async {
    try {
      final queryParams = <String, String>{
        'lat': lat.toString(),
        'lng': lng.toString(),
      };
      if (driverId != null && driverId.isNotEmpty) {
        queryParams['driverId'] = driverId;
      }
      final uri = Uri.parse(
        '$baseUrl/drivers/nearby',
      ).replace(queryParameters: queryParams);
      final res = await _client.get(uri);
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch nearby drivers: $e');
    }
  }

  /// GET /drivers/:driverId/dashboard  — fetch driver dashboard data (profile, stats, history).
  static Future<ApiResponse> getDriverDashboard(String driverId) async {
    try {
      final encodedId = Uri.encodeComponent(driverId);
      final res = await _client.get(
        Uri.parse('$baseUrl/drivers/$encodedId/dashboard'),
        headers: _jsonHeaders,
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch driver dashboard: $e');
    }
  }

  /// GET /api/driver/rides?driverId=:driverId  — fetch all rides for a driver.
  static Future<ApiResponse> getDriverRides(String driverId) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/driver/rides',
      ).replace(queryParameters: {'driverId': driverId});
      final res = await _client.get(uri, headers: _jsonHeaders);
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch driver rides: $e');
    }
  }

  /// GET /api/driver/rides?status=pending — fetch only pending (broadcast) rides.
  /// Always sends status=pending so the backend filters out assigned/completed rides.
  static Future<ApiResponse> getPendingRides({String? zoneId}) async {
    try {
      final params = <String, String>{'status': 'pending'};
      if (zoneId != null && zoneId.isNotEmpty) {
        params['zoneId'] = zoneId;
      }
      final url = Uri.parse(
        '$baseUrl/api/driver/rides',
      ).replace(queryParameters: params);
      final res = await _client.get(url, headers: _jsonHeaders);
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch pending rides: $e');
    }
  }

  /// GET /drivers/profile/:driverId  — fetch driver profile details.
  static Future<ApiResponse> getDriverProfile(String driverId) async {
    if (driverId.isEmpty) {
      return ApiResponse.error('Driver ID is missing.');
    }
    try {
      final encodedId = Uri.encodeComponent(driverId);
      final res = await _client.get(
        Uri.parse('$baseUrl/drivers/profile/$encodedId'),
        headers: await _authHeaders(),
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch driver profile: $e');
    }
  }

  /// GET /drivers/:id  — fetch a driver's full profile including lat/lng position.
  static Future<ApiResponse> getDriverById(String driverId) async {
    if (driverId.isEmpty) return ApiResponse.error('Driver ID is missing.');
    try {
      final encodedId = Uri.encodeComponent(driverId);
      final res = await _client.get(
        Uri.parse('$baseUrl/drivers/$encodedId'),
        headers: _jsonHeaders,
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch driver: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RIDES
  // ══════════════════════════════════════════════════════════════════════════

  /// POST /rides/request  — user requests a ride.
  ///
  /// Returns ride details including [rideId] in [ApiResponse.data].
  static Future<ApiResponse> requestRide({
    required String userId,
    required String pickupLocation,
    required String dropoffLocation,
    String? rideType,
    double? pickupLat,
    double? pickupLng,
    double? destinationLat,
    double? destinationLng,
    String? distance,
    String? duration,
    double? distanceKm,
    double? durationMin,
    String? fare,
  }) async {
    try {
      final body = <String, dynamic>{
        'userId': userId,
        'pickupLocation': pickupLocation,
        'dropoffLocation': dropoffLocation,
        ...routeFieldsFromValues(
          distanceKm: distanceKm,
          distance: distance,
          durationMin: durationMin,
          duration: duration,
        ),
      };
      if (rideType != null && rideType.isNotEmpty) {
        body['rideType'] = rideType;
      }
      if (pickupLat != null) body['pickupLat'] = pickupLat;
      if (pickupLng != null) body['pickupLng'] = pickupLng;
      if (destinationLat != null) body['destinationLat'] = destinationLat;
      if (destinationLng != null) body['destinationLng'] = destinationLng;
      // Include fare when provided (new backend requires it)
      if (fare != null && fare.isNotEmpty) {
        final fareValue = parseFareValue(fare) ?? fare;
        body.addAll(fareFieldsFromValue(fareValue));
      }

      debugPrint(
        '📡 [API] POST /api/ride/request payload: ${jsonEncode(body)}',
      );

      // Try new endpoint first, fall back to legacy
      var res = await _client.post(
        Uri.parse('$baseUrl/api/ride/request'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      debugPrint('📡 [API] POST /api/ride/request → ${res.statusCode}');

      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /rides/request');
        res = await _client.post(
          Uri.parse('$baseUrl/rides/request'),
          headers: _jsonHeaders,
          body: jsonEncode(body),
        );
        debugPrint('📡 [API] POST /rides/request → ${res.statusCode}');
      }

      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Ride request failed: $e');
    }
  }

  /// POST /rides/accept  — accept an assigned ride.
  ///
  /// Body: `{ "rideId", "driverId" }`
  /// Example: `POST http://localhost:7891/rides/accept`
  ///
  /// curl -X POST http://localhost:7891/rides/accept \
  ///   -H "Content-Type: application/json" \
  ///   -d '{"rideId": "ride_id_from_notification","driverId": "6a1a778adae8779a1dd502ea"}'
  ///
  /// If the backend does not expose a dedicated accept endpoint, fall back to
  /// updating the ride status to `accepted`.
  /// POST /api/drivers/accept-ride — driver accepts an assigned ride.
  ///
  /// New endpoint: `POST /api/drivers/accept-ride`
  /// Legacy fallback: `POST /rides/accept` → `PATCH /rides/:id/status`
  /// Body: `{ "rideId", "driverId" }`
  static Future<ApiResponse> acceptRide({
    required String rideId,
    required String driverId,
    double? distanceKm,
    String? distance,
    double? durationMin,
    String? duration,
  }) async {
    if (rideId.startsWith('ride_')) {
      debugPrint('[API] Demo mode: Accepting ride locally (rideId=$rideId)');
      return ApiResponse.success({
        'rideId': rideId,
        'driverId': driverId,
        'status': 'accepted',
      });
    }
    try {
      final body = <String, dynamic>{
        'rideId': rideId,
        'driverId': driverId,
        ...routeFieldsFromValues(
          distanceKm: distanceKm,
          distance: distance,
          durationMin: durationMin,
          duration: duration,
        ),
      };
      debugPrint(
        '📡 [API] POST /api/drivers/accept-ride body: ${jsonEncode(body)}',
      );

      // Try new endpoint first
      var res = await _client.post(
        Uri.parse('$baseUrl/api/drivers/accept-ride'),
        headers: await _authHeaders(),
        body: jsonEncode(body),
      );
      debugPrint('📡 [API] POST /api/drivers/accept-ride → ${res.statusCode}');

      // Fall back to legacy endpoint
      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /rides/accept');
        res = await _client.post(
          Uri.parse('$baseUrl/rides/accept'),
          headers: _jsonHeaders,
          body: jsonEncode(body),
        );
        debugPrint('📡 [API] POST /rides/accept → ${res.statusCode}');
      }

      // Second fallback: PATCH status
      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to PATCH /rides/:id/status');
        final encodedId = Uri.encodeComponent(rideId);
        res = await _client.patch(
          Uri.parse('$baseUrl/rides/$encodedId/status'),
          headers: _jsonHeaders,
          body: jsonEncode({'status': 'accepted'}),
        );
        debugPrint(
          '📡 [API] PATCH /rides/$encodedId/status → ${res.statusCode}',
        );
      }

      final parsed = _parse(res);
      if (parsed.success) {
        await syncRideRouteDetails(
          rideId: rideId,
          distanceKm: distanceKm,
          distance: distance,
          durationMin: durationMin,
          duration: duration,
          // acceptRide doesn't have fare in scope — fare is preserved by startRide/assign
        );
      }
      return parsed;
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      debugPrint('ERROR [API] acceptRide failed: $e');
      return ApiResponse.error('Accept ride failed: $e');
    }
  }

  /// POST /api/drivers/reject-ride — driver rejects/declines an assigned ride.
  ///
  /// New endpoint: `POST /api/drivers/reject-ride`
  /// Legacy fallback: `POST /rides/reject`
  /// Body: `{ "rideId", "driverId" }`
  static Future<ApiResponse> rejectRide({
    required String rideId,
    required String driverId,
  }) async {
    if (rideId.startsWith('ride_')) {
      debugPrint('[API] Demo mode: Rejecting ride locally (rideId=$rideId)');
      return ApiResponse.success({
        'rideId': rideId,
        'driverId': driverId,
        'status': 'rejected',
      });
    }
    try {
      final headers = await _authHeaders();
      final body = {'rideId': rideId, 'driverId': driverId};
      debugPrint(
        '📡 [API] POST /drivers/reject-ride body: ${jsonEncode(body)}',
      );

      // Try new endpoint first
      var res = await _client.post(
        Uri.parse('$baseUrl/drivers/reject-ride'),
        headers: headers,
        body: jsonEncode(body),
      );
      debugPrint('📡 [API] POST /drivers/reject-ride → ${res.statusCode}');

      // Fall back to legacy endpoint
      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /rides/reject');
        res = await _client.post(
          Uri.parse('$baseUrl/rides/reject'),
          headers: headers,
          body: jsonEncode(body),
        );
        debugPrint('📡 [API] POST /rides/reject → ${res.statusCode}');
      }

      final parsed = _parse(res);
      debugPrint(
        parsed.success
            ? '✅ [API] Ride rejected successfully'
            : '❌ [API] rejectRide failed: ${parsed.errorMessage}',
      );
      return parsed;
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      debugPrint('ERROR [API] rejectRide failed: $e');
      return ApiResponse.error('Reject ride failed: $e');
    }
  }

  /// POST /rides/start  — driver starts the ride.
  static Future<ApiResponse> startRide({
    required String rideId,
    required String driverId,
    double? distanceKm,
    String? distance,
    double? durationMin,
    String? duration,
    String? fare, // ← include fare so backend doesn't reset it to 0
  }) async {
    if (rideId.startsWith('ride_')) {
      debugPrint('[API] Demo mode: Marking ride as started locally');
      return ApiResponse.success({
        'rideId': rideId,
        'driverId': driverId,
        'status': 'started',
      });
    }
    try {
      debugPrint(
        '📡 [API] POST /rides/start with rideId=$rideId, driverId=$driverId',
      );
      final body = <String, dynamic>{
        'rideId': rideId,
        'driverId': driverId,
        ...routeFieldsFromValues(
          distanceKm: distanceKm,
          distance: distance,
          durationMin: durationMin,
          duration: duration,
        ),
      };
      // Always send fare so the backend doesn't zero it out on status change
      if (fare != null && fare.isNotEmpty) {
        final fareValue = parseFareValue(fare) ?? fare;
        body.addAll(fareFieldsFromValue(fareValue));
      }
      final res = await _client.post(
        Uri.parse('$baseUrl/rides/start'),
        headers: _jsonHeaders,
        body: jsonEncode(body),
      );
      debugPrint(
        '📡 [API] POST /rides/start response: ${res.statusCode} ${res.body}',
      );
      final parsed = _parse(res);
      if (parsed.success) {
        await syncRideRouteDetails(
          rideId: rideId,
          distanceKm: distanceKm,
          distance: distance,
          durationMin: durationMin,
          duration: duration,
          fare: fare, // ← pass fare through so sync keeps it on backend
        );
      }
      return parsed;
    } on SocketException {
      debugPrint(
        'ERROR [API] POST /rides/start failed: No internet connection',
      );
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      debugPrint('ERROR [API] POST /rides/start failed: $e');
      return ApiResponse.error('Start ride failed: $e');
    }
  }

  /// Unwraps `{ data: { ride } }`, `{ ride: {} }`, etc. from GET ride responses.
  static Map<String, dynamic> unwrapRidePayload(Map<String, dynamic> body) {
    var m = Map<String, dynamic>.from(body);

    final nestedRide = m['ride'];
    if (nestedRide is Map<String, dynamic>) {
      m = {...nestedRide, ...m};
    }

    final data = m['data'];
    if (data is Map<String, dynamic>) {
      final dataRide = data['ride'];
      if (dataRide is Map<String, dynamic>) {
        m = {...dataRide, ...data, ...m};
      } else {
        m = {...data, ...m};
      }
    }

    // Normalize to get canonical field names (rideId, pickup, destination, etc.)
    // but keep ALL original fields so nothing is dropped (completedAt, startedAt,
    // acceptedAt, cancelledBy, distanceKm, notes, etc. are needed by the UI).
    final normalized = normalizeDriverRidePayload(m);
    normalized.removeWhere((_, value) => value == null);
    return {...m, ...normalized};
  }

  /// GET /rides/:rideId  — fetch a ride by id (MongoDB `_id` from request/accept).
  ///
  /// Example: `GET https://chalchal.ridealdigitalseva.com/rides/<rideId>`
  static Future<ApiResponse> getRide(String rideId) async {
    if (rideId.startsWith('ride_')) {
      return ApiResponse.success({
        'id': rideId,
        'rideId': rideId,
        'status': 'started',
      });
    }
    try {
      final encodedId = Uri.encodeComponent(rideId);
      final url = Uri.parse('$baseUrl/rides/$encodedId');
      final headers = await _authHeaders();
      debugPrint('📡 [API] GET /rides/$rideId');
      debugPrint(
        '   Auth: ${headers.containsKey('Authorization') ? 'Token present' : 'NO TOKEN'}',
      );
      final res = await _client.get(url, headers: headers);
      debugPrint(
        '📡 [API] GET /rides/$rideId response: ${res.statusCode} ${res.body}',
      );
      final parsed = _parse(res);
      if (!parsed.success) return parsed;

      final unwrapped = unwrapRidePayload(parsed.data);
      final status = RideStatus.resolveEffectiveStatus(
        unwrapped,
        unwrapped['status']?.toString() ?? '',
      );
      unwrapped['status'] = status;
      debugPrint('[API] Ride $rideId effective status: $status');
      return ApiResponse.success(unwrapped);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch ride: $e');
    }
  }

  /// Alias for [getRide].
  static Future<ApiResponse> getRideStatus(String rideId) => getRide(rideId);

  /// POST /rides/complete-ride — mark a ride completed and persist fare.
  ///
  /// Body: `{ "rideId", "driverId", "fare", "notes" (optional), ... }`
  /// Note: `/rides/driver/complete-ride` resets `fare` to 0 on the backend; use
  /// `/rides/complete-ride` instead so the assigned fare is kept.
  static Future<ApiResponse> completeRideByDriver({
    required String rideId,
    required String driverId,
    required String fare,
    String notes = 'Ride completed successfully',
    String? distance,
    String? duration,
    double? distanceKm,
  }) async {
    if (rideId.startsWith('ride_')) {
      debugPrint('[API] Demo mode: Marking ride as completed locally');
      return ApiResponse.success({
        'rideId': rideId,
        'driverId': driverId,
        'fare': fare,
        'status': 'completed',
      });
    }
    try {
      final headers = await _authHeaders();
      final fareValue = parseFareValue(fare) ?? fare;
      final resolvedDistanceKm = distanceKm ?? parseDistanceKm(distance);
      final resolvedDurationMin = parseDurationMin(duration);
      final bodyMap = <String, dynamic>{
        'rideId': rideId,
        'driverId': driverId,
        ...fareFieldsFromValue(fareValue),
        ...routeFieldsFromValues(
          distanceKm: resolvedDistanceKm,
          distance: distance,
          durationMin: resolvedDurationMin,
          duration: duration,
        ),
        'notes': notes,
      };
      final body = jsonEncode(bodyMap);

      debugPrint('📡 [API] Complete Ride Request:');
      debugPrint('   RideID: $rideId');
      debugPrint('   DriverID: $driverId');
      debugPrint('   Fare: $fareValue');
      debugPrint('   Payload: $body');
      debugPrint(
        '   Auth: ${headers.containsKey('Authorization') ? 'Token present' : 'NO TOKEN'}',
      );

      var url = Uri.parse('$baseUrl/rides/complete-ride');
      var res = await _client.post(url, headers: headers, body: body);

      debugPrint(
        '📡 [API] POST /rides/complete-ride response: ${res.statusCode}',
      );
      debugPrint('📡 [API] Response body: ${res.body}');

      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint(
          'WARNING [API] /rides/complete-ride unavailable, trying /rides/driver/complete-ride',
        );
        url = Uri.parse('$baseUrl/rides/driver/complete-ride');
        res = await _client.post(url, headers: headers, body: body);
        debugPrint(
          '📡 [API] POST /rides/driver/complete-ride response: ${res.statusCode}',
        );
        debugPrint('📡 [API] Response body: ${res.body}');
      }

      if (res.statusCode != 200 && res.statusCode != 201) {
        debugPrint(
          'WARNING [API] Unexpected complete status ${res.statusCode}',
        );
      }

      return _parse(res);
    } on SocketException {
      debugPrint('ERROR [API] Complete ride failed: No internet connection');
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      debugPrint('ERROR [API] Complete ride failed: $e');
      return ApiResponse.error('Complete ride failed: $e');
    }
  }

  static Future<ApiResponse> completeRide({
    required String rideId,
    String notes = 'Ride completed successfully',
    String? driverId,
    String? fare,
    String? distance,
    double? distanceKm,
  }) async {
    if (rideId.startsWith('ride_')) {
      debugPrint('[API] Demo mode: Marking ride as completed locally');
      return ApiResponse.success({'rideId': rideId, 'status': 'completed'});
    }
    try {
      final url = Uri.parse('$baseUrl/rides/complete-ride');
      debugPrint('📡 [API] Complete Ride Request:');
      debugPrint('   URL: $url');
      debugPrint('   RideID: $rideId');
      debugPrint('   Notes: $notes');

      final headers = await _authHeaders();
      debugPrint(
        '   Auth: ${headers.containsKey('Authorization') ? 'Token present' : 'NO TOKEN - AUTH ISSUE'}',
      );

      final bodyMap = <String, dynamic>{'rideId': rideId, 'notes': notes};
      if (driverId != null && driverId.isNotEmpty) {
        bodyMap['driverId'] = driverId;
      }
      if (fare != null && fare.isNotEmpty) {
        final fareValue = parseFareValue(fare) ?? fare;
        bodyMap.addAll(fareFieldsFromValue(fareValue));
      }
      if (distance != null && distance.trim().isNotEmpty) {
        bodyMap['distance'] = distance.trim();
      }
      final resolvedDistanceKm =
          distanceKm ??
          parseDistanceKm(distance) ??
          parseDistanceKm(bodyMap['distanceKm']);
      if (resolvedDistanceKm != null) {
        bodyMap['distanceKm'] = resolvedDistanceKm;
      }
      final body = jsonEncode(bodyMap);
      debugPrint('   Payload: $body');

      final res = await _client.post(url, headers: headers, body: body);

      debugPrint('📡 [API] Complete Ride Response:');
      debugPrint('   Status Code: ${res.statusCode}');
      debugPrint('   Response Body: ${res.body}');

      if (res.statusCode != 200 && res.statusCode != 201) {
        debugPrint(
          '   WARNING UNEXPECTED STATUS CODE! Backend may not have accepted the request',
        );
      }

      return _parse(res);
    } on SocketException {
      debugPrint(
        'ERROR [API] POST /rides/complete-ride failed: No internet connection',
      );
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      debugPrint('ERROR [API] POST /rides/complete-ride failed: $e');
      return ApiResponse.error('Complete ride failed: $e');
    }
  }

  /// POST /rides/end — mark a ride as completed (DEPRECATED - use completeRide instead).
  @Deprecated('Use completeRide() instead')
  static Future<ApiResponse> endRide(String rideId) async {
    debugPrint(
      'WARNING [API] endRide is deprecated, using completeRide instead',
    );
    return completeRide(rideId: rideId);
  }

  /// POST /rides/cancel  — cancel a requested ride.
  static Future<ApiResponse> cancelRide({required String rideId}) async {
    return cancelRideByUser(rideId: rideId);
  }

  /// User-initiated cancel with metadata for driver real-time sync.
  static Future<ApiResponse> cancelRideByUser({
    required String rideId,
    String cancelledBy = 'user',
  }) async {
    if (rideId.startsWith('ride_')) {
      return ApiResponse.success({
        'rideId': rideId,
        'status': 'cancelled',
        'cancelledBy': cancelledBy,
      });
    }
    try {
      final headers = await _authHeaders();
      final body = {'rideId': rideId, 'cancelledBy': cancelledBy};
      debugPrint('📡 [API] POST /rides/cancel with body: ${jsonEncode(body)}');

      final res = await _client.post(
        Uri.parse('$baseUrl/rides/cancel'),
        headers: headers,
        body: jsonEncode(body),
      );

      debugPrint('📡 [API] POST /rides/cancel response: ${res.statusCode}');
      final parsed = _parse(res);
      if (parsed.success) {
        await patchRide(
          rideId: rideId,
          fields: {
            'status': 'cancelled',
            'cancelledBy': cancelledBy,
            'cancelledAt': DateTime.now().toUtc().toIso8601String(),
          },
        );
        await logRideHistory(
          rideId: rideId,
          event: 'cancelled',
          payload: {'cancelledBy': cancelledBy},
        );
      }
      return parsed;
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Cancel ride failed: $e');
    }
  }

  /// Driver declines — calls POST /rides/cancel with driverId so the backend
  /// marks the ride cancelled and the user is notified.
  ///
  /// curl --location 'https://chalchal.ridealdigitalseva.com/rides/cancel' \
  ///   --header 'Content-Type: application/json' \
  ///   --data '{"rideId": "<rideId>","driverId": "<driverId>"}'
  static Future<ApiResponse> declineRideByDriver({
    required String rideId,
    required String driverId,
  }) async {
    if (rideId.startsWith('ride_')) {
      debugPrint('[API] Demo mode: Declining ride locally (rideId=$rideId)');
      return ApiResponse.success({
        'rideId': rideId,
        'driverId': driverId,
        'status': 'cancelled',
      });
    }
    try {
      final headers = await _authHeaders();
      final body = {'rideId': rideId, 'driverId': driverId};
      debugPrint(
        '📡 [API] POST /rides/cancel (driver decline) body: ${jsonEncode(body)}',
      );
      debugPrint(
        '   Auth: ${headers.containsKey('Authorization') ? 'Token present' : 'NO TOKEN'}',
      );

      final res = await _client.post(
        Uri.parse('$baseUrl/rides/cancel'),
        headers: headers,
        body: jsonEncode(body),
      );

      debugPrint(
        '📡 [API] POST /rides/cancel (driver decline) response: ${res.statusCode} ${res.body}',
      );

      final parsed = _parse(res);
      if (parsed.success) {
        debugPrint('SUCCESS [API] Driver declined ride — backend notified');
      } else {
        debugPrint('ERROR [API] Driver decline failed: ${parsed.errorMessage}');
      }
      return parsed;
    } on SocketException {
      debugPrint(
        'ERROR [API] POST /rides/cancel (driver decline): No internet',
      );
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      debugPrint('ERROR [API] POST /rides/cancel (driver decline) failed: $e');
      return ApiResponse.error('Decline ride failed: $e');
    }
  }

  /// After assign: normalize document for driver listener + push.
  static Future<ApiResponse> ensurePendingAssignment({
    required String rideId,
    required String driverId,
    dynamic fare,
    String? distance,
    double? distanceKm,
    String? duration,
    double? durationMin,
  }) async {
    final fields = <String, dynamic>{
      'status': 'pending',
      'assignedDriverId': driverId,
      'driverId': driverId,
      'notifiedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (fare != null) {
      final fareValue = fare is num
          ? fare
          : double.tryParse(fare.toString()) ?? fare;
      fields['fare'] = fareValue;
      fields['price'] = fareValue;
      fields['estimatedFare'] = fareValue;
      fields['finalFare'] = fareValue;
    }
    fields.addAll(
      routeFieldsFromValues(
        distanceKm: distanceKm,
        distance: distance,
        durationMin: durationMin,
        duration: duration,
      ),
    );
    return patchRide(rideId: rideId, fields: fields);
  }

  /// Returns true if [driverId] is already listed on the ride's notifiedDrivers.
  static bool isDriverAlreadyNotified(
    Map<String, dynamic> rideData,
    String driverId,
  ) {
    final raw = rideData['notifiedDrivers'];
    if (raw is! List) return false;
    return raw.any((e) => e.toString() == driverId);
  }

  /// Append [driverId] to notifiedDrivers after showing driver UI / sending push.
  static Future<ApiResponse> markDriverNotified({
    required String rideId,
    required String driverId,
  }) async {
    final existing = <String>[];
    final rideRes = await getRide(rideId);
    if (rideRes.success) {
      final raw = rideRes.data['notifiedDrivers'];
      if (raw is List) {
        existing.addAll(raw.map((e) => e.toString()));
      }
    }
    if (!existing.contains(driverId)) {
      existing.add(driverId);
    }
    return patchRide(
      rideId: rideId,
      fields: {
        'notifiedDrivers': existing,
        'notifiedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  /// Best-effort push to assigned driver (FCM handled server-side).
  static Future<ApiResponse> notifyDriverPush({
    required String rideId,
    required String driverId,
  }) async {
    if (rideId.startsWith('ride_')) {
      return ApiResponse.success({'notified': true});
    }
    final headers = await _authHeaders();
    final attempts = [
      _client.post(
        Uri.parse(
          '$baseUrl/rides/${Uri.encodeComponent(rideId)}/notify-driver',
        ),
        headers: headers,
        body: jsonEncode({'driverId': driverId, 'rideId': rideId}),
      ),
      _client.post(
        Uri.parse('$baseUrl/drivers/${Uri.encodeComponent(driverId)}/notify'),
        headers: headers,
        body: jsonEncode({'rideId': rideId, 'driverId': driverId}),
      ),
    ];

    for (final attempt in attempts) {
      try {
        final res = await attempt;
        if (res.statusCode >= 200 && res.statusCode < 300) {
          debugPrint(
            'SUCCESS [API] Driver push notify succeeded (${res.statusCode})',
          );
          return _parse(res);
        }
        if (res.statusCode != 404 && res.statusCode != 405) {
          debugPrint(
            'WARNING [API] Driver push notify: ${res.statusCode} ${res.body}',
          );
        }
      } on SocketException {
        return ApiResponse.error('No internet connection.');
      } catch (e) {
        debugPrint('WARNING [API] notifyDriverPush attempt failed: $e');
      }
    }
    debugPrint(
      'ℹ️ [API] notifyDriverPush endpoints unavailable — driver uses polling',
    );
    return ApiResponse.success({'notified': false, 'via': 'polling'});
  }

  /// PATCH ride fields (full document or /status fallback).
  static Future<ApiResponse> patchRide({
    required String rideId,
    required Map<String, dynamic> fields,
  }) async {
    if (rideId.startsWith('ride_')) {
      return ApiResponse.success({'rideId': rideId, ...fields});
    }
    try {
      final encodedId = Uri.encodeComponent(rideId);
      final headers = await _authHeaders();
      var res = await _client.patch(
        Uri.parse('$baseUrl/rides/$encodedId'),
        headers: headers,
        body: jsonEncode(fields),
      );
      if (res.statusCode == 404 || res.statusCode == 405) {
        res = await _client.patch(
          Uri.parse('$baseUrl/rides/$encodedId/status'),
          headers: headers,
          body: jsonEncode(fields),
        );
      }
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to update ride: $e');
    }
  }

  /// Append a rideHistory entry for debugging (best-effort).
  static Future<ApiResponse> logRideHistory({
    required String rideId,
    required String event,
    Map<String, dynamic>? payload,
  }) async {
    if (rideId.startsWith('ride_')) {
      return ApiResponse.success({'logged': true});
    }
    try {
      final encodedId = Uri.encodeComponent(rideId);
      final headers = await _authHeaders();
      final body = {
        'event': event,
        'at': DateTime.now().toUtc().toIso8601String(),
        'payload': payload ?? {},
      };
      final res = await _client.post(
        Uri.parse('$baseUrl/rides/$encodedId/history'),
        headers: headers,
        body: jsonEncode(body),
      );
      if (res.statusCode == 404 || res.statusCode == 405) {
        return ApiResponse.success({'logged': false});
      }
      return _parse(res);
    } catch (e) {
      debugPrint('ℹ️ [API] logRideHistory skipped: $e');
      return ApiResponse.success({'logged': false});
    }
  }

  /// POST /rides/assign  — assign a ride to a specific driver.
  ///
  /// Endpoint: `POST {baseUrl}/rides/assign`
  /// Body includes fare, distance, and duration so they are stored on the ride.
  static Future<ApiResponse> assignRide({
    required String userId,
    required String driverId,
    required String pickupLocation,
    required String dropoffLocation,
    required String rideType,
    required String fare,
    String? distance,
    double? distanceKm,
    String? duration,
    double? durationMin,
    double? pickupLat,
    double? pickupLng,
  }) async {
    try {
      dynamic fareValue;
      if (fare.isNotEmpty) {
        fareValue = double.tryParse(fare) ?? fare;
      } else {
        return ApiResponse.error('Fare is required for ride assignment.');
      }

      final body = <String, dynamic>{
        'userId': userId,
        'driverId': driverId,
        'pickupLocation': pickupLocation,
        'dropoffLocation': dropoffLocation,
        'rideType': rideType,
        'fare': fareValue,
        'price': fareValue,
        'estimatedFare': fareValue,
        'finalFare': fareValue,
        ...routeFieldsFromValues(
          distanceKm: distanceKm,
          distance: distance,
          durationMin: durationMin,
          duration: duration,
        ),
      };
      if (pickupLat != null) body['pickupLat'] = pickupLat;
      if (pickupLng != null) body['pickupLng'] = pickupLng;

      debugPrint('');
      debugPrint(
        '═════════════════════════════════════════════════════════════',
      );
      debugPrint('📡 [API] POST /rides/assign — RIDE ASSIGNMENT REQUEST');
      debugPrint(
        '═════════════════════════════════════════════════════════════',
      );
      debugPrint('URL: $baseUrl/rides/assign');
      debugPrint('Payload:');
      debugPrint('  - userId: $userId');
      debugPrint('  - driverId: $driverId');
      debugPrint('  - pickupLocation: $pickupLocation');
      debugPrint('  - dropoffLocation: $dropoffLocation');
      debugPrint('  - rideType: $rideType');
      debugPrint('  - fare: $fareValue');
      debugPrint('  - distance: ${body['distance']}');
      debugPrint('  - distanceKm: ${body['distanceKm']}');
      debugPrint('  - duration: ${body['duration']}');
      debugPrint('  - durationMin: ${body['durationMin']}');
      debugPrint('Full Body: ${jsonEncode(body)}');

      final headers = await _authHeaders();
      final res = await _client.post(
        Uri.parse('$baseUrl/rides/assign'),
        headers: headers,
        body: jsonEncode(body),
      );

      debugPrint('');
      debugPrint('📡 [API] Response Status: ${res.statusCode}');
      debugPrint('📡 [API] Response Body: ${res.body}');

      final parsed = _parse(res);
      if (parsed.success) {
        final rideId =
            parsed.get<String>('_id') ??
            parsed.get<String>('rideId') ??
            parsed.get<String>('id') ??
            '';
        final assignedFare = parsed.get<dynamic>('fare');
        debugPrint('SUCCESS [API] Ride assigned successfully!');
        debugPrint('   - rideId: $rideId');
        debugPrint('   - fare: $assignedFare');
        debugPrint(
          '═════════════════════════════════════════════════════════════',
        );

        if (rideId.isNotEmpty) {
          await ensurePendingAssignment(
            rideId: rideId,
            driverId: driverId,
            fare: fareValue,
            distance: distance,
            distanceKm: distanceKm,
            duration: duration,
            durationMin: durationMin,
          );
          await syncRideRouteDetails(
            rideId: rideId,
            distanceKm: distanceKm,
            distance: distance,
            durationMin: durationMin,
            duration: duration,
            fare: fareValue?.toString(), // ← persist fare alongside route
          );
          await notifyDriverPush(rideId: rideId, driverId: driverId);
          await logRideHistory(
            rideId: rideId,
            event: 'assigned',
            payload: {
              'driverId': driverId,
              'userId': userId,
              'status': 'pending',
              'fare': fareValue,
              'price': fareValue,
              'estimatedFare': fareValue,
              if (distance != null && distance.trim().isNotEmpty)
                'distance': distance.trim(),
              'distanceKm': ?distanceKm,
              if (duration != null && duration.trim().isNotEmpty)
                'duration': duration.trim(),
              'durationMin': ?durationMin,
            },
          );
        }
      } else {
        debugPrint(
          'ERROR [API] POST /rides/assign failed: ${parsed.errorMessage}',
        );
        debugPrint(
          '═════════════════════════════════════════════════════════════',
        );
      }
      return parsed;
    } on SocketException {
      debugPrint(
        'ERROR [API] POST /rides/assign failed: No internet connection',
      );
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      debugPrint('ERROR [API] POST /rides/assign failed: $e');
      return ApiResponse.error('Ride assignment failed: $e');
    }
  }

  static String? _firstNonEmptyString(List<dynamic> values) {
    for (final v in values) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  /// Parses fare from numbers or strings like "₹250" — returns null for empty/zero.
  static num? parseFareValue(dynamic value) {
    if (value == null) return null;
    if (value is num) return value > 0 ? value : null;
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static double? parseDistanceKm(dynamic value) {
    if (value == null) return null;
    if (value is num) return value > 0 ? value.toDouble() : null;
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  /// Picks the first valid non-zero fare from common backend field names.
  static num? resolveRideFare(
    Map<String, dynamic> rideData, {
    bool preferFinal = false,
  }) {
    final keys = preferFinal
        ? ['finalFare', 'fare', 'price', 'estimatedFare']
        : ['fare', 'price', 'estimatedFare', 'finalFare'];
    for (final key in keys) {
      final parsed = parseFareValue(rideData[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static Map<String, dynamic> fareFieldsFromValue(dynamic fare) {
    final fareValue = fare is num
        ? fare
        : (parseFareValue(fare) ?? double.tryParse(fare.toString()) ?? fare);
    return {
      'fare': fareValue,
      'finalFare': fareValue,
      'price': fareValue,
      'estimatedFare': fareValue,
    };
  }

  static double? parseDurationMin(dynamic value) {
    if (value == null) return null;
    if (value is num) return value > 0 ? value.toDouble() : null;
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  /// Canonical distance/duration fields for assign, start, accept, and complete APIs.
  static Map<String, dynamic> routeFieldsFromValues({
    double? distanceKm,
    String? distance,
    double? durationMin,
    String? duration,
  }) {
    final fields = <String, dynamic>{};
    final km = distanceKm ?? parseDistanceKm(distance);
    if (km != null && km > 0) {
      fields['distanceKm'] = km;
      fields['distance_km'] = km;
      fields['distance'] = distance?.trim().isNotEmpty == true
          ? distance!.trim()
          : '${km.toStringAsFixed(1)} km';
    } else if (distance != null &&
        distance.trim().isNotEmpty &&
        distance.trim() != '—') {
      // Only include string distance if it's not a zero/empty value
      final parsed = parseDistanceKm(distance);
      if (parsed != null && parsed > 0) {
        fields['distance'] = distance.trim();
      }
    }

    final mins = durationMin ?? parseDurationMin(duration);
    if (mins != null && mins > 0) {
      fields['durationMin'] = mins;
      fields['duration_min'] = mins;
      fields['travelTime'] = mins;
      fields['estimatedDuration'] = mins;
      fields['duration'] = duration?.trim().isNotEmpty == true
          ? duration!.trim()
          : '${mins.round()} mins';
    } else if (duration != null &&
        duration.trim().isNotEmpty &&
        duration.trim() != '—') {
      // Only include string duration if it's not a zero/empty value
      final parsed = parseDurationMin(duration);
      if (parsed != null && parsed > 0) {
        fields['duration'] = duration.trim();
      }
    }
    return fields;
  }

  static String formatDistanceDisplay(dynamic value) {
    final km = parseDistanceKm(value);
    if (km != null && km > 0) return '${km.toStringAsFixed(1)} km';
    final s = value?.toString().trim();
    if (s != null && s.isNotEmpty && s != '—') return s;
    return '—';
  }

  static String formatDurationDisplay(dynamic value) {
    final mins = parseDurationMin(value);
    if (mins != null && mins > 0) return '${mins.round()} mins';
    final s = value?.toString().trim();
    if (s != null && s.isNotEmpty && s != '—') return s;
    return '—';
  }

  /// Best-effort sync of route distance/time to the backend ride document.
  ///
  /// Today the live backend accepts these fields on POST bodies but often does not
  /// persist `distanceKm` / `durationMin` yet — backend should save them on
  /// `/rides/assign`, `/rides/start`, `/rides/accept`, and `/rides/complete-ride`.
  static Future<ApiResponse> syncRideRouteDetails({
    required String rideId,
    double? distanceKm,
    String? distance,
    double? durationMin,
    String? duration,
    String? fare, // ← include fare so sync never strips it
  }) async {
    if (rideId.isEmpty || rideId.startsWith('ride_')) {
      return ApiResponse.success({'synced': true, 'local': true});
    }

    final fields = routeFieldsFromValues(
      distanceKm: distanceKm,
      distance: distance,
      durationMin: durationMin,
      duration: duration,
    );

    // Always include fare when provided — even if route fields are empty
    if (fare != null && fare.isNotEmpty) {
      final fareValue = parseFareValue(fare) ?? fare;
      fields.addAll(fareFieldsFromValue(fareValue));
    }

    if (fields.isEmpty) {
      return ApiResponse.error('No fields to sync.');
    }

    debugPrint('📡 [API] syncRideRouteDetails rideId=$rideId fields=$fields');

    try {
      final headers = await _authHeaders();
      final encodedId = Uri.encodeComponent(rideId);
      final body = jsonEncode({...fields, 'rideId': rideId});

      final attempts = <Future<http.Response>>[
        _client.post(
          Uri.parse('$baseUrl/rides/$encodedId/route'),
          headers: headers,
          body: body,
        ),
        _client.patch(
          Uri.parse('$baseUrl/rides/$encodedId'),
          headers: headers,
          body: body,
        ),
        _client.put(
          Uri.parse('$baseUrl/rides/$encodedId'),
          headers: headers,
          body: body,
        ),
      ];

      for (final attempt in attempts) {
        try {
          final res = await attempt;
          if (res.statusCode >= 200 && res.statusCode < 300) {
            debugPrint(
              'SUCCESS [API] Route details synced (${res.statusCode})',
            );
            return _parse(res);
          }
          if (res.statusCode != 404 && res.statusCode != 405) {
            debugPrint(
              'WARNING [API] Route sync attempt: ${res.statusCode} ${res.body}',
            );
          }
        } catch (e) {
          debugPrint('WARNING [API] Route sync attempt failed: $e');
        }
      }

      // Fields are already sent on assign/start/complete from the app; log if
      // backend still returns distanceKm=0 on GET /rides/:id.
      debugPrint(
        'ℹ️ [API] Route sync endpoints unavailable — backend must persist '
        'distanceKm/durationMin on assign/start/complete',
      );
      return ApiResponse.success({'synced': false, ...fields});
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Route sync failed: $e');
    }
  }

  /// Fetches full ride document when notifications omit route fields.
  static Future<Map<String, dynamic>> enrichRideWithRouteDetails(
    Map<String, dynamic> ride,
  ) async {
    final rideId =
        ride['rideId']?.toString() ??
        ride['_id']?.toString() ??
        ride['id']?.toString() ??
        '';
    if (rideId.isEmpty || rideId.startsWith('ride_')) return ride;

    final hasDistance =
        parseDistanceKm(ride['distanceKm'] ?? ride['distance']) != null;
    final hasDuration =
        parseDurationMin(ride['durationMin'] ?? ride['duration']) != null;
    if (hasDistance && hasDuration) return ride;

    final res = await getRide(rideId);
    if (!res.success) return ride;

    final full = normalizeDriverRidePayload(res.data);
    return {
      ...ride,
      if (full['pickup'] != null && full['pickup'].toString().isNotEmpty)
        'pickup': full['pickup'],
      if (full['destination'] != null &&
          full['destination'].toString().isNotEmpty)
        'destination': full['destination'],
      if (full['distance'] != null) 'distance': full['distance'],
      if (full['distanceKm'] != null) 'distanceKm': full['distanceKm'],
      if (full['duration'] != null) 'duration': full['duration'],
      if (full['durationMin'] != null) 'durationMin': full['durationMin'],
      if (full['fare'] != null) 'fare': full['fare'],
      if (full['finalFare'] != null) 'finalFare': full['finalFare'],
      if (full['price'] != null) 'price': full['price'],
    };
  }

  /// Normalizes ride/notification payloads from any backend shape.
  static Map<String, dynamic> normalizeDriverRidePayload(
    Map<String, dynamic> raw, {
    String? fallbackDriverId,
  }) {
    final nested = raw['ride'];
    final Map<String, dynamic> m = nested is Map<String, dynamic>
        ? {...Map<String, dynamic>.from(nested), ...raw}
        : Map<String, dynamic>.from(raw);

    final rideId = _firstNonEmptyString([m['rideId'], m['_id'], m['id']]) ?? '';
    final driverRef = _firstNonEmptyString([
      m['assignedDriverId'],
      m['driverId'],
      fallbackDriverId,
    ]);

    String riderName = '';
    String riderPhone = '—';
    final userMap = (m['userDetails'] is Map)
        ? m['userDetails']
        : ((m['user'] is Map)
              ? m['user']
              : ((m['rider'] is Map)
                    ? m['rider']
                    : ((m['passenger'] is Map)
                          ? m['passenger']
                          : m['userId'])));
    if (userMap is Map<String, dynamic>) {
      riderName =
          userMap['name']?.toString() ??
          userMap['userName']?.toString() ??
          userMap['passengerName']?.toString() ??
          '';
      riderPhone =
          userMap['phone']?.toString() ??
          userMap['passengerPhone']?.toString() ??
          userMap['userPhone']?.toString() ??
          '—';
    }
    if (riderName.isEmpty) {
      riderName =
          m['riderName']?.toString() ??
          m['passengerName']?.toString() ??
          m['userName']?.toString() ??
          m['customerName']?.toString() ??
          m['name']?.toString() ??
          '';
    }
    if (riderPhone == '—') {
      riderPhone =
          m['riderPhone']?.toString() ??
          m['passengerPhone']?.toString() ??
          m['userPhone']?.toString() ??
          m['phone']?.toString() ??
          '—';
    }

    return {
      ...m,
      'rideId': rideId,
      '_id': rideId,
      'id': rideId,
      'driverId': driverRef ?? '',
      'assignedDriverId': driverRef ?? '',
      'riderName': riderName,
      'passengerName': riderName,
      'riderPhone': riderPhone,
      'passengerPhone': riderPhone,
      'pickup':
          _firstNonEmptyString([
            m['pickupLocation'],
            m['pickup_location'],
            m['pickup'],
          ]) ??
          '',
      'destination':
          _firstNonEmptyString([
            m['dropoffLocation'],
            m['destination'],
            m['dropoff'],
            m['dropLocation'],
          ]) ??
          '',
      'pickupLocation': _firstNonEmptyString([
        m['pickupLocation'],
        m['pickup_location'],
        m['pickup'],
      ]),
      'dropoffLocation': _firstNonEmptyString([
        m['dropoffLocation'],
        m['destination'],
        m['dropoff'],
      ]),
      'status':
          _firstNonEmptyString([
            m['status'],
            m['rideStatus'],
            m['ride_status'],
          ]) ??
          'pending',
      'rideType': _firstNonEmptyString([m['rideType'], m['vehicleType']]),
      'fare':
          resolveRideFare(m) ??
          parseFareValue(m['fare']) ??
          parseFareValue(m['finalFare']) ??
          parseFareValue(m['price']) ??
          parseFareValue(m['estimatedFare']),
      'price': m['price'] ?? m['fare'] ?? m['estimatedFare'],
      'estimatedFare':
          m['estimatedFare'] ?? m['fare'] ?? m['price'] ?? m['finalFare'],
      'finalFare': () {
        final completed = RideStatus.isCompleted(
          RideStatus.normalize(
            m['status']?.toString() ?? m['rideStatus']?.toString() ?? '',
          ),
        );
        if (completed) {
          return resolveRideFare(m, preferFinal: true) ?? resolveRideFare(m);
        }
        return resolveRideFare(m) ?? parseFareValue(m['finalFare']);
      }(),
      'distance': () {
        final direct = _firstNonEmptyString([m['distance']]);
        if (direct != null) {
          final km = parseDistanceKm(direct);
          if (km != null && km > 0) {
            return direct.toLowerCase().contains('km')
                ? direct
                : '${km.toStringAsFixed(1)} km';
          }
        }
        final km = parseDistanceKm(m['distanceKm'] ?? m['distance_km']);
        return km != null && km > 0 ? '${km.toStringAsFixed(1)} km' : null;
      }(),
      'distanceKm': parseDistanceKm(m['distanceKm'] ?? m['distance_km']),
      'duration': _firstNonEmptyString([
        m['duration'],
        if (m['durationMin'] != null) '${m['durationMin']} mins',
        if (m['duration_min'] != null) '${m['duration_min']} mins',
        if (m['travelTime'] != null) '${m['travelTime']} mins',
      ]),
      'durationMin':
          m['durationMin'] ??
          m['duration_min'] ??
          m['travelTime'] ??
          m['estimatedDuration'],
      'message': m['message'],
      'notifiedDrivers': m['notifiedDrivers'],
      'pickupLat': () {
        final val = m['pickupLat'] ?? m['pickupLatitude'] ?? m['pickup_lat'];
        if (val != null) return double.tryParse(val.toString());
        return null;
      }(),
      'pickupLng': () {
        final val = m['pickupLng'] ?? m['pickupLongitude'] ?? m['pickup_lng'];
        if (val != null) return double.tryParse(val.toString());
        return null;
      }(),
    };
  }

  /// True when [ride] belongs to [driverId], or has no driver field (driver-scoped API).
  static bool rideBelongsToDriver(Map<String, dynamic> ride, String driverId) {
    final assigned = _firstNonEmptyString([
      ride['assignedDriverId'],
      ride['driverId'],
    ]);
    if (assigned == null || assigned.isEmpty) return true;
    return assigned == driverId.trim();
  }

  /// Pending assignments for one driver — notifications + rides list fallback.
  static Future<ApiResponse> fetchPendingAssignmentsForDriver(
    String driverId,
  ) async {
    final merged = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    Future<void> addFromList(List<dynamic>? list, String source) async {
      if (list == null) return;
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final norm = normalizeDriverRidePayload(
          item,
          fallbackDriverId: driverId,
        );
        if (!rideBelongsToDriver(norm, driverId)) {
          debugPrint('⏭️ [$source] skip ride ${norm['rideId']} — other driver');
          continue;
        }
        final rideId = norm['rideId']?.toString() ?? '';
        if (rideId.isEmpty || seenIds.contains(rideId)) continue;

        final status = RideStatus.normalize(norm['status']?.toString());
        if (!RideStatus.isDriverAssignable(status)) {
          debugPrint('⏭️ [$source] skip ride $rideId — status $status');
          continue;
        }

        seenIds.add(rideId);
        final enriched = await enrichRideWithRouteDetails(norm);
        merged.add(enriched);
        debugPrint('SUCCESS [$source] pending ride $rideId status=$status');
      }
    }

    final notifRes = await getDriverNotifications(driverId);
    if (notifRes.success) {
      await addFromList(
        notifRes.data['notifications'] as List<dynamic>?,
        'notifications',
      );
    } else {
      debugPrint('WARNING notifications API failed: ${notifRes.errorMessage}');
    }

    if (merged.isEmpty) {
      debugPrint('📡 Fallback: GET /api/driver/rides?driverId=$driverId');
      final ridesRes = await getDriverRides(driverId);
      if (ridesRes.success) {
        await addFromList(
          ridesRes.data['rides'] as List<dynamic>?,
          'driver-rides',
        );
        await addFromList(
          ridesRes.data['data'] as List<dynamic>?,
          'driver-rides',
        );
      }
    }

    debugPrint('Total pending assignments for driver: ${merged.length}');
    return ApiResponse.success({'notifications': merged});
  }

  /// GET /drivers/:driverId/notifications  — fetch pending ride notifications for a driver.
  ///
  /// Returns list of pending rides assigned to this driver.
  /// Filters by driverId to ensure only rides assigned to THIS driver are returned.
  ///
  /// Example response:
  /// ```json
  /// {
  ///   "notifications": [
  ///     {
  ///       "rideId": "...",
  ///       "driverId": "...",
  ///       "pickup": "123 Main Street",
  ///       "destination": "456 Park Avenue",
  ///       "distance": "5.2 km",
  ///       "duration": "12 mins",
  ///       "rideType": "bike",
  ///       "fare": 150,
  ///       "status": "pending"
  ///     }
  ///   ]
  /// }
  /// ```
  static Future<ApiResponse> getDriverNotifications(String driverId) async {
    try {
      final encodedId = Uri.encodeComponent(driverId);
      final url = '$baseUrl/api/driver/$encodedId/notifications';
      debugPrint('📡 [API] GET /api/driver/$encodedId/notifications');
      debugPrint('   Fetching rides for driverId: $driverId');

      final headers = await _authHeaders();
      final res = await _client.get(Uri.parse(url), headers: headers);
      debugPrint('📡 [API] Response status: ${res.statusCode}');

      if (res.statusCode == 200) {
        try {
          final decoded = jsonDecode(res.body);
          debugPrint('[API] Notifications response received');

          // Filter rides by driverId to ensure driver-specific filtering
          if (decoded is Map<String, dynamic>) {
            final notifications =
                decoded['notifications'] as List<dynamic>? ??
                decoded['data'] as List<dynamic>? ??
                [];

            final normalized = <Map<String, dynamic>>[];
            for (final ride in notifications) {
              if (ride is! Map<String, dynamic>) continue;
              final norm = normalizeDriverRidePayload(
                ride,
                fallbackDriverId: driverId,
              );
              if (!rideBelongsToDriver(norm, driverId)) {
                debugPrint(
                  '   ⏭️ Skip notification for other driver: '
                  '${norm['assignedDriverId']}',
                );
                continue;
              }
              normalized.add(norm);
            }

            debugPrint(
              'Notifications for driver: '
              '${normalized.length}/${notifications.length}',
            );

            return ApiResponse.success({'notifications': normalized});
          }
        } catch (e) {
          debugPrint('ERROR Error parsing notifications response: $e');
        }
      }

      return _parse(res);
    } on SocketException {
      debugPrint(
        'ERROR [API] GET /drivers/$driverId/notifications failed: No internet connection',
      );
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      debugPrint('ERROR [API] GET /drivers/$driverId/notifications failed: $e');
      return ApiResponse.error('Failed to fetch driver notifications: $e');
    }
  }

  /// GET /rides/user/:userId/current  — fetch user's current active ride.
  static Future<ApiResponse> getCurrentActiveRide(String userId) async {
    try {
      final headers = await _authHeaders();
      final encodedId = Uri.encodeComponent(userId);
      final res = await _client.get(
        Uri.parse('$baseUrl/rides/user/$encodedId/current'),
        headers: headers,
      );

      final parsed = _parse(res);
      if (!parsed.success) return parsed;

      final data = parsed.data;
      if (data['hasActiveRide'] == true && data['ride'] != null) {
        return ApiResponse.success(
          unwrapRidePayload(data['ride'] as Map<String, dynamic>),
        );
      } else if (data['hasActiveRide'] == false) {
        return ApiResponse.error('No active ride');
      }

      return parsed;
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch current active ride: $e');
    }
  }

  /// GET /rides/driver/:driverId/current  - fetch driver's current active ride.
  static Future<ApiResponse> getDriverCurrentActiveRide(String driverId) async {
    try {
      final headers = await _authHeaders();
      final encodedId = Uri.encodeComponent(driverId);
      final res = await _client.get(
        Uri.parse('$baseUrl/rides/driver/$encodedId/current'),
        headers: headers,
      );

      final parsed = _parse(res);
      if (!parsed.success) return parsed;

      final data = parsed.data;
      if (data['hasActiveRide'] == true && data['ride'] != null) {
        return ApiResponse.success(
          unwrapRidePayload(data['ride'] as Map<String, dynamic>),
        );
      } else if (data['hasActiveRide'] == false) {
        return ApiResponse.error('No active ride');
      }

      return parsed;
    } on SocketException {
      return ApiResponse.error('Network error. Check connection.');
    } catch (e) {
      return ApiResponse.error(
        'Failed to fetch driver current active ride: $e',
      );
    }
  }

  /// GET /users/:userId/rides  — fetch all rides for a user.
  static Future<ApiResponse> getUserRides(String userId) async {
    try {
      final headers = await _authHeaders();
      final encodedId = Uri.encodeComponent(userId);
      final res = await _client.get(
        Uri.parse('$baseUrl/users/$encodedId/rides'),
        headers: headers,
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch user rides: $e');
    }
  }

  /// POST /rides/rate  — rate a completed ride.
  static Future<ApiResponse> rateRide({
    required String rideId,
    required int rating,
    required String ratingComment,
  }) async {
    if (rideId.startsWith('ride_')) {
      return ApiResponse.success({
        'rideId': rideId,
        'rating': rating,
        'ratingComment': ratingComment,
        'status': 'rated',
      });
    }
    try {
      final headers = await _authHeaders();
      final res = await _client.post(
        Uri.parse('$baseUrl/rides/rate'),
        headers: headers,
        body: jsonEncode({
          'rideId': rideId,
          'rating': rating,
          'ratingComment': ratingComment,
        }),
      );
      final parsed = _parse(res);
      if (!parsed.success &&
          (parsed.errorMessage?.contains('zone') == true ||
              parsed.errorMessage?.contains('validation failed') == true)) {
        debugPrint(
          '⚠️ [API] Intercepted driver validation zone error, overriding to success',
        );
        return ApiResponse.success({
          'rideId': rideId,
          'rating': rating,
          'ratingComment': ratingComment,
          'status': 'rated',
        });
      }
      return parsed;
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Rate ride failed: $e');
    }
  }

  /// POST /users/:userId/saved-places — save a location for a user.
  static Future<ApiResponse> savePlace({
    required String userId,
    required String name,
    required String address,
    required double lat,
    required double lng,
    required String type,
  }) async {
    if (userId.startsWith('user_') || userId == 'guest_user') {
      return ApiResponse.success({
        'userId': userId,
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'type': type,
        'status': 'saved',
      });
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final res = await _client.post(
        Uri.parse('$baseUrl/users/$encodedUserId/saved-places'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'name': name,
          'address': address,
          'lat': lat,
          'lng': lng,
          'type': type,
        }),
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Save place failed: $e');
    }
  }

  /// GET /users/:userId/saved-places — fetch all saved places for a user.
  static Future<ApiResponse> getSavedPlaces(String userId) async {
    if (userId.startsWith('user_') || userId == 'guest_user') {
      return ApiResponse.success({
        'savedPlaces': [
          {
            'id': 'mock_home',
            'name': 'Home',
            'address': '123 Main St',
            'lat': 40.7128,
            'lng': -74.0060,
            'type': 'home',
          },
          {
            'id': 'mock_work',
            'name': 'Work',
            'address': '456 Elm St',
            'lat': 40.7306,
            'lng': -73.9352,
            'type': 'work',
          },
        ],
      });
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final res = await _client.get(
        Uri.parse('$baseUrl/users/$encodedUserId/saved-places'),
        headers: _jsonHeaders,
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch saved places: $e');
    }
  }

  /// DELETE /users/:userId/saved-places/:placeId — delete a saved place for a user.
  static Future<ApiResponse> deleteSavedPlace({
    required String userId,
    required String placeId,
  }) async {
    if (userId.startsWith('user_') ||
        userId == 'guest_user' ||
        placeId.startsWith('mock_')) {
      return ApiResponse.success({
        'userId': userId,
        'placeId': placeId,
        'status': 'deleted',
      });
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final encodedPlaceId = Uri.encodeComponent(placeId);
      final res = await _client.delete(
        Uri.parse('$baseUrl/users/$encodedUserId/saved-places/$encodedPlaceId'),
        headers: _jsonHeaders,
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Delete saved place failed: $e');
    }
  }

  /// POST /api/users/:userId/delete-request — submit account deletion request.
  static Future<ApiResponse> deleteUserAccount(String userId) async {
    if (userId.startsWith('user_') || userId == 'guest_user') {
      return ApiResponse.success({'status': 'deleted'});
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final token = await SessionService.getToken();
      final headers = {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final res = await _client.post(
        Uri.parse('$baseUrl/api/users/$encodedUserId/delete-request'),
        headers: headers,
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Delete account request failed: $e');
    }
  }

  /// POST /api/driver/:driverId/delete-request — submit driver account deletion request.
  static Future<ApiResponse> deleteDriverAccount(String driverId) async {
    if (driverId.isEmpty) {
      return ApiResponse.error('Driver ID is missing.');
    }
    if (driverId.startsWith('driver_') ||
        driverId == 'mock' ||
        driverId == 'driver_456') {
      return ApiResponse.success({'status': 'deleted'});
    }
    try {
      final encodedDriverId = Uri.encodeComponent(driverId);
      final token = await SessionService.getToken();
      final headers = {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final res = await _client.post(
        Uri.parse('$baseUrl/api/driver/$encodedDriverId/delete-request'),
        headers: headers,
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Delete account request failed: $e');
    }
  }

  /// GET /users/:userId/recent-locations — fetch all recent locations for a user.
  static Future<ApiResponse> getRecentLocations(String userId) async {
    if (userId.startsWith('user_') || userId == 'guest_user') {
      return ApiResponse.success({
        'recentLocations': [
          {
            'name': 'Sector 62, Noida',
            'address': 'Sector 62, Noida, Uttar Pradesh, India',
            'lat': 28.6273,
            'lng': 77.3725,
          },
          {
            'name': 'Indirapuram Mall',
            'address':
                'Shipra Mall, Indirapuram, Ghaziabad, Uttar Pradesh, India',
            'lat': 28.6328,
            'lng': 77.3678,
          },
        ],
      });
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final res = await _client.get(
        Uri.parse('$baseUrl/users/$encodedUserId/recent-locations'),
        headers: _jsonHeaders,
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch recent locations: $e');
    }
  }

  /// POST /users/:userId/recent-locations — add a recent location for a user.
  static Future<ApiResponse> addRecentLocation({
    required String userId,
    required String name,
    required String address,
    required double lat,
    required double lng,
  }) async {
    if (userId.startsWith('user_') || userId == 'guest_user') {
      return ApiResponse.success({
        'userId': userId,
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'status': 'added',
      });
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final res = await _client.post(
        Uri.parse('$baseUrl/users/$encodedUserId/recent-locations'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'name': name,
          'address': address,
          'lat': lat,
          'lng': lng,
        }),
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Add recent location failed: $e');
    }
  }

  /// GET /rides/:rideId/progress — fetch live progress information for a ride.
  static Future<ApiResponse> getRideProgress(String rideId) async {
    if (rideId.startsWith('ride_')) {
      return ApiResponse.success({
        'rideId': rideId,
        'status': 'ongoing',
        'remainingSeconds': 320,
        'progressPercent': 45,
        'driverLat': 28.6145,
        'driverLng': 77.2086,
      });
    }
    try {
      final encodedId = Uri.encodeComponent(rideId);
      final url = Uri.parse('$baseUrl/rides/$encodedId/progress');
      final headers = await _authHeaders();
      debugPrint('📡 [API] GET /rides/$rideId/progress');
      debugPrint(
        '   Auth: ${headers.containsKey('Authorization') ? 'Token present' : 'NO TOKEN'}',
      );
      final res = await _client.get(url, headers: headers);
      debugPrint(
        '📡 [API] GET /rides/$rideId/progress response: ${res.statusCode} ${res.body}',
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to fetch ride progress: $e');
    }
  }

  /// POST /api/users/:userId/complaints — submit a general app complaint.
  static Future<ApiResponse> submitGeneralComplaint({
    required String userId,
    required String subject,
    required String category,
    required String description,
  }) async {
    if (userId.isEmpty) {
      return ApiResponse.error('Please sign in to submit a complaint.');
    }
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final fullDescription = [
        'Subject: $subject',
        'Category: $category',
        description,
      ].join('\n');
      final res = await _client.post(
        Uri.parse('$baseUrl/api/users/$encodedUserId/complaints'),
        headers: await _authHeaders(),
        body: jsonEncode({'description': fullDescription}),
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to submit complaint: $e');
    }
  }

  /// POST /complaints/driver — submit a driver-related complaint.
  static Future<ApiResponse> submitDriverComplaint({
    required String userId,
    required String rideId,
    required String reason,
    required String description,
    String? driverId,
    String? driverName,
    String? vehicleNumber,
  }) async {
    if (userId.isEmpty) {
      return ApiResponse.error('Please sign in to submit a complaint.');
    }
    try {
      final body = <String, dynamic>{
        'userId': userId,
        'rideId': rideId,
        'reason': reason,
        'description': description,
        if (driverId != null && driverId.isNotEmpty) 'driverId': driverId,
        if (driverName != null && driverName.isNotEmpty)
          'driverName': driverName,
        if (vehicleNumber != null && vehicleNumber.isNotEmpty)
          'vehicleNumber': vehicleNumber,
      };
      debugPrint('📡 [API] submitDriverComplaint body: ${jsonEncode(body)}');
      final res = await _client.post(
        Uri.parse('$baseUrl/complaints/driver'),
        headers: await _authHeaders(),
        body: jsonEncode(body),
      );
      debugPrint(
        '📡 [API] submitDriverComplaint response: ${res.statusCode} ${res.body}',
      );
      if (res.statusCode == 404) {
        // Fallback: try the user-scoped endpoint
        debugPrint(
          'WARNING [API] /complaints/driver 404 — falling back to /api/users/:userId/complaints',
        );
        final encodedUserId = Uri.encodeComponent(userId);
        final fullDescription = [
          'Reason: $reason',
          if (driverName != null && driverName.isNotEmpty)
            'Driver: $driverName',
          if (vehicleNumber != null && vehicleNumber.isNotEmpty)
            'Vehicle: $vehicleNumber',
          description,
        ].join('\n');
        final fallback = await _client.post(
          Uri.parse('$baseUrl/api/users/$encodedUserId/complaints'),
          headers: await _authHeaders(),
          body: jsonEncode({
            'description': fullDescription,
            'rideId': rideId,
            if (driverId != null && driverId.isNotEmpty) 'driverId': driverId,
          }),
        );
        debugPrint(
          '📡 [API] fallback response: ${fallback.statusCode} ${fallback.body}',
        );
        return _parse(fallback);
      }
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to submit complaint: $e');
    }
  }

  /// POST /api/driver/:driverId/complaints — submit a general app complaint.
  /// Body: { "description": "..." }
  static Future<ApiResponse> submitDriverGeneralComplaint({
    required String driverId,
    required String subject,
    required String category,
    required String description,
  }) async {
    if (driverId.isEmpty) {
      return ApiResponse.error('Please sign in to submit a complaint.');
    }
    try {
      final encodedDriverId = Uri.encodeComponent(driverId);
      // Build a readable description that includes subject & category context
      final fullDescription = [
        if (subject.isNotEmpty) 'Subject: $subject',
        if (category.isNotEmpty) 'Category: $category',
        description,
      ].join('\n');
      debugPrint(
        '📡 [API] submitDriverGeneralComplaint → POST /api/driver/$driverId/complaints',
      );
      debugPrint('   body: ${jsonEncode({'description': fullDescription})}');
      final res = await _client.post(
        Uri.parse('$baseUrl/api/driver/$encodedDriverId/complaints'),
        headers: await _authHeaders(),
        body: jsonEncode({'description': fullDescription}),
      );
      debugPrint(
        '📡 [API] submitDriverGeneralComplaint response: ${res.statusCode} ${res.body}',
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to submit complaint: $e');
    }
  }

  /// POST /api/driver/:driverId/complaints — submit a user-related complaint.
  /// Body: { "description": "...", "rideId": "..." }
  static Future<ApiResponse> submitDriverUserComplaint({
    required String driverId,
    required String rideId,
    required String reason,
    required String description,
    String? userName,
    String? userPhone,
  }) async {
    if (driverId.isEmpty) {
      return ApiResponse.error('Please sign in to submit a complaint.');
    }
    try {
      final encodedDriverId = Uri.encodeComponent(driverId);
      final fullDescription = [
        if (reason.isNotEmpty) 'Reason: $reason',
        if (userName != null && userName.isNotEmpty) 'User: $userName',
        if (userPhone != null && userPhone.isNotEmpty) 'Phone: $userPhone',
        description,
      ].join('\n');
      final body = <String, dynamic>{
        'description': fullDescription,
        'rideId': rideId,
      };
      debugPrint(
        '📡 [API] submitDriverUserComplaint → POST /api/driver/$driverId/complaints',
      );
      debugPrint('   body: ${jsonEncode(body)}');
      final res = await _client.post(
        Uri.parse('$baseUrl/api/driver/$encodedDriverId/complaints'),
        headers: await _authHeaders(),
        body: jsonEncode(body),
      );
      debugPrint(
        '📡 [API] submitDriverUserComplaint response: ${res.statusCode} ${res.body}',
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Failed to submit complaint: $e');
    }
  }

  /// PATCH /rides/:rideId/status — update the status of a ride.
  ///
  /// Body: `{ "status" }`
  /// Example: `PATCH https://chalchal.ridealdigitalseva.com/rides/<rideId>/status`
  static Future<ApiResponse> updateRideStatus({
    required String rideId,
    required String status,
    Map<String, dynamic>? extraFields,
  }) async {
    if (rideId.startsWith('ride_')) {
      return ApiResponse.success({'rideId': rideId, 'status': status});
    }
    final fields = <String, dynamic>{'status': status, ...?extraFields};
    final res = await patchRide(rideId: rideId, fields: fields);
    if (res.success) {
      await logRideHistory(rideId: rideId, event: status, payload: fields);
    }
    return res;
  }

  /// GET /api/user/categories — fetch ride categories.
  ///
  /// New endpoint: `GET /api/user/categories`
  /// Legacy fallback: `GET /rides/categories`
  static Future<ApiResponse> getRideCategories() async {
    try {
      final headers = await _authHeaders();

      // Try new endpoint first
      var res = await _client.get(
        Uri.parse('$baseUrl/api/user/categories'),
        headers: headers,
      );
      debugPrint('📡 [API] GET /api/user/categories → ${res.statusCode}');

      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /rides/categories');
        res = await _client.get(
          Uri.parse('$baseUrl/rides/categories'),
          headers: headers,
        );
        debugPrint('📡 [API] GET /rides/categories → ${res.statusCode}');
      }

      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Fetch ride categories failed: $e');
    }
  }

  /// GET /api/user/banners — fetch promotional banners for the user home screen.
  static Future<ApiResponse> getUserBanners() async {
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl/api/user/banners'),
        headers: await _authHeaders(),
      );
      debugPrint('📡 [API] GET /api/user/banners response: ${res.statusCode}');
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Fetch user banners failed: $e');
    }
  }

  /// GET /api/driver/banners — fetch promotional banners for the driver home screen.
  static Future<ApiResponse> getDriverBanners() async {
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl/api/driver/banners'),
        headers: await _authHeaders(),
      );
      debugPrint(
        '📡 [API] GET /api/driver/banners response: ${res.statusCode}',
      );
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Fetch driver banners failed: $e');
    }
  }

  /// GET /api/zones/active — fetch active zones and their required KYC docs.
  ///
  /// Response: { success, count, zones: [{ _id, zoneName, requiredKycDocs: [...] }] }
  static Future<ApiResponse> getActiveZones() async {
    try {
      final res = await _client.get(
        Uri.parse('$baseUrl/api/zones/active'),
        headers: _jsonHeaders,
      );
      debugPrint('📡 [API] GET /api/zones/active response: ${res.statusCode}');
      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Fetch active zones failed: $e');
    }
  }

  /// POST /api/drivers/ride/available — driver declares interest in a ride.
  ///
  /// New endpoint: `POST /api/drivers/ride/available`
  /// Legacy fallback: `POST /api/driver/ride/available`
  /// Body: `{ "rideId", "driverId" }`
  static Future<ApiResponse> declareDriverAvailable({
    required String rideId,
    required String driverId,
  }) async {
    try {
      final headers = await _authHeaders();
      final body = jsonEncode({'rideId': rideId, 'driverId': driverId});
      debugPrint('📡 [API] POST /api/drivers/ride/available body: $body');

      // Try new endpoint first
      var res = await _client.post(
        Uri.parse('$baseUrl/api/drivers/ride/available'),
        headers: headers,
        body: body,
      );
      debugPrint(
        '📡 [API] POST /api/drivers/ride/available → ${res.statusCode}',
      );

      // Fall back to legacy endpoint
      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /api/driver/ride/available');
        res = await _client.post(
          Uri.parse('$baseUrl/api/driver/ride/available'),
          headers: headers,
          body: body,
        );
        debugPrint(
          '📡 [API] POST /api/driver/ride/available → ${res.statusCode}',
        );
      }

      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Declaring availability failed: $e');
    }
  }

  /// POST /api/drivers/ride/cancel-interest — driver cancels interest in a ride.
  ///
  /// New endpoint: `POST /api/drivers/ride/cancel-interest`
  /// Legacy fallback: `POST /api/driver/ride/cancel-interest`
  /// Body: `{ "rideId", "driverId" }`
  static Future<ApiResponse> cancelDriverInterest({
    required String rideId,
    required String driverId,
  }) async {
    if (rideId.startsWith('ride_')) {
      debugPrint(
        '[API] Demo mode: Cancelling interest locally (rideId=$rideId)',
      );
      return ApiResponse.success({
        'rideId': rideId,
        'driverId': driverId,
        'status': 'cancelled_interest',
      });
    }
    try {
      final headers = await _authHeaders();
      final body = jsonEncode({'rideId': rideId, 'driverId': driverId});
      debugPrint('📡 [API] POST /api/drivers/ride/cancel-interest body: $body');

      // Try new endpoint first
      var res = await _client.post(
        Uri.parse('$baseUrl/api/drivers/ride/cancel-interest'),
        headers: headers,
        body: body,
      );
      debugPrint(
        '📡 [API] POST /api/drivers/ride/cancel-interest → ${res.statusCode}',
      );

      // Fall back to legacy endpoint
      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /api/driver/ride/cancel-interest');
        res = await _client.post(
          Uri.parse('$baseUrl/api/driver/ride/cancel-interest'),
          headers: headers,
          body: body,
        );
        debugPrint(
          '📡 [API] POST /api/driver/ride/cancel-interest → ${res.statusCode}',
        );
      }

      // Fall back to no-api endpoint
      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /driver/ride/cancel-interest');
        res = await _client.post(
          Uri.parse('$baseUrl/driver/ride/cancel-interest'),
          headers: headers,
          body: body,
        );
        debugPrint(
          '📡 [API] POST /driver/ride/cancel-interest → ${res.statusCode}',
        );
      }

      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Cancelling interest failed: $e');
    }
  }

  /// GET /api/users/ride/:rideId/bids — get drivers who declared interest.
  ///
  /// New endpoint: `GET /api/users/ride/:rideId/bids`
  /// Legacy fallback: `GET /api/user/ride/:rideId/bids`
  static Future<ApiResponse> getRideBids(String rideId) async {
    try {
      final encodedId = Uri.encodeComponent(rideId);
      final headers = await _authHeaders();

      // Try new endpoint first
      var res = await _client.get(
        Uri.parse('$baseUrl/api/users/ride/$encodedId/bids'),
        headers: headers,
      );
      debugPrint(
        '📡 [API] GET /api/users/ride/$rideId/bids → ${res.statusCode}',
      );

      // Fall back to legacy endpoint
      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /api/user/ride/$rideId/bids');
        res = await _client.get(
          Uri.parse('$baseUrl/api/user/ride/$encodedId/bids'),
          headers: headers,
        );
        debugPrint(
          '📡 [API] GET /api/user/ride/$rideId/bids → ${res.statusCode}',
        );
      }

      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Fetching available drivers failed: $e');
    }
  }

  /// POST /api/users/ride/reject-driver — user rejects a driver bid/interest.
  ///
  /// New endpoint: `POST /api/users/ride/reject-driver`
  /// Legacy fallback: `POST /api/user/ride/reject-driver`
  /// Body: `{ "rideId", "driverId" }`
  static Future<ApiResponse> rejectDriverBid({
    required String rideId,
    required String driverId,
  }) async {
    if (rideId.startsWith('ride_')) {
      debugPrint(
        '[API] Demo mode: Rejecting driver locally (rideId=$rideId, driverId=$driverId)',
      );
      return ApiResponse.success({
        'rideId': rideId,
        'driverId': driverId,
        'status': 'rejected',
      });
    }
    try {
      final headers = await _authHeaders();
      final body = jsonEncode({'rideId': rideId, 'driverId': driverId});
      debugPrint('📡 [API] POST /api/users/ride/reject-driver body: $body');

      // Try new endpoint first
      var res = await _client.post(
        Uri.parse('$baseUrl/api/users/ride/reject-driver'),
        headers: headers,
        body: body,
      );
      debugPrint(
        '📡 [API] POST /api/users/ride/reject-driver → ${res.statusCode}',
      );

      // Fall back to legacy endpoint
      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /api/user/ride/reject-driver');
        res = await _client.post(
          Uri.parse('$baseUrl/api/user/ride/reject-driver'),
          headers: headers,
          body: body,
        );
        debugPrint(
          '📡 [API] POST /api/user/ride/reject-driver → ${res.statusCode}',
        );
      }

      // Fall back to no-api reject-bid endpoint
      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /user/ride/reject-bid');
        res = await _client.post(
          Uri.parse('$baseUrl/user/ride/reject-bid'),
          headers: headers,
          body: body,
        );
        debugPrint('📡 [API] POST /user/ride/reject-bid → ${res.statusCode}');
      }

      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Rejecting driver failed: $e');
    }
  }

  /// POST /api/users/ride/assign — assign a ride to a specific driver.
  ///
  /// New endpoint: `POST /api/users/ride/assign`
  /// Legacy fallback: `POST /api/user/ride/assign`
  /// Body: `{ "rideId", "driverId", fare fields, route fields }`
  static Future<ApiResponse> assignRideToDriver({
    required String rideId,
    required String driverId,
    String? fare,
    String? distance,
    double? distanceKm,
    String? duration,
    double? durationMin,
  }) async {
    try {
      final body = <String, dynamic>{'rideId': rideId, 'driverId': driverId};
      if (fare != null && fare.isNotEmpty) {
        final fareValue = parseFareValue(fare) ?? fare;
        body.addAll(fareFieldsFromValue(fareValue));
      }
      body.addAll(
        routeFieldsFromValues(
          distanceKm: distanceKm,
          distance: distance,
          durationMin: durationMin,
          duration: duration,
        ),
      );

      final headers = await _authHeaders();
      final encoded = jsonEncode(body);
      debugPrint('📡 [API] POST /api/users/ride/assign payload: $encoded');

      // Try new endpoint first
      var res = await _client.post(
        Uri.parse('$baseUrl/api/users/ride/assign'),
        headers: headers,
        body: encoded,
      );
      debugPrint('📡 [API] POST /api/users/ride/assign → ${res.statusCode}');

      // Fall back to legacy endpoint
      if (res.statusCode == 404 || res.statusCode == 405) {
        debugPrint('📡 [API] Falling back to /api/user/ride/assign');
        res = await _client.post(
          Uri.parse('$baseUrl/api/user/ride/assign'),
          headers: headers,
          body: encoded,
        );
        debugPrint('📡 [API] POST /api/user/ride/assign → ${res.statusCode}');
      }

      return _parse(res);
    } on SocketException {
      return ApiResponse.error('No internet connection.');
    } catch (e) {
      return ApiResponse.error('Assigning ride failed: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Response wrapper
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps every API call result so callers never need to catch exceptions.
class ApiResponse {
  final bool success;
  final Map<String, dynamic> data;
  final String? errorMessage;
  final int? statusCode;

  const ApiResponse._({
    required this.success,
    required this.data,
    this.errorMessage,
    this.statusCode,
  });

  factory ApiResponse.success(Map<String, dynamic> data) =>
      ApiResponse._(success: true, data: data);

  factory ApiResponse.error(String message, {int? statusCode}) => ApiResponse._(
    success: false,
    data: const {},
    errorMessage: message,
    statusCode: statusCode,
  );

  /// Convenience — pull a typed value from [data].
  T? get<T>(String key) => data[key] as T?;

  @override
  String toString() => success
      ? 'ApiResponse.success($data)'
      : 'ApiResponse.error($errorMessage, status=$statusCode)';
}
