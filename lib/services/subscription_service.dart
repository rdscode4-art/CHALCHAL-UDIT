import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/services/session_service.dart';
import '../core/services/api_service.dart';
import '../models/subscription_model.dart';

/// Driver subscription state + API calls.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  SubscriptionModel? _subscription;
  List<SubscriptionPlanItem> _plans = const [];
  double _performanceDistanceKm = 0;
  bool _loadingSubscription = false;
  bool _loadingPlans = false;
  String? _lastError;

  // Razorpay helper variables
  Razorpay? _razorpay;
  Completer<bool>? _paymentCompleter;
  String? _pendingPlanId;
  String? _pendingDriverId;

  SubscriptionModel? get subscription => _subscription;
  List<SubscriptionPlanItem> get plans => _plans;
  double get performanceDistanceKm => _performanceDistanceKm;
  bool get isLoadingSubscription => _loadingSubscription;
  bool get isLoadingPlans => _loadingPlans;
  String? get lastError => _lastError;

  bool get isBlocked => _subscription?.status.isBlocked ?? false;

  /// KM used for subscription UI.
  double get effectiveKmUsed => _subscription?.kmUsed ?? 0;

  double? get effectiveKmLimit => _subscription?.kmLimit;

  double get effectiveKmRemaining => _subscription?.kmRemaining ?? 0;

  double? get usageProgress {
    final limit = effectiveKmLimit;
    if (limit == null || limit <= 0) return null;
    return (effectiveKmUsed / limit).clamp(0.0, 1.0);
  }

  void updatePerformanceDistance(double km) {
    if ((_performanceDistanceKm - km).abs() < 0.01) return;
    _performanceDistanceKm = km;
    notifyListeners();
  }

  Future<SubscriptionModel?> fetchSubscription() async {
    _loadingSubscription = true;
    _lastError = null;
    notifyListeners();

    try {
      final driverId = await SessionService.getDriverId() ?? '';
      double totalDistanceKm = 0.0;
      if (driverId.isNotEmpty) {
        // Fetch the dashboard data to get the latest real performance distance from the backend
        final dashRes = await ApiService.getDriverDashboard(driverId);
        if (dashRes.success) {
          final stats = dashRes.data['stats'] as Map<String, dynamic>?;
          if (stats != null) {
            totalDistanceKm =
                double.tryParse(
                  stats['totalDistanceKm']?.toString() ?? '0.0',
                ) ??
                0.0;
          }
        } else {
          // Fallback: Fetch rides and calculate total distance if dashboard API is unavailable
          final ridesRes = await ApiService.getDriverRides(driverId);
          if (ridesRes.success) {
            final ridesList = ridesRes.data['rides'] as List<dynamic>? ?? [];
            for (final item in ridesList) {
              if (item is Map<String, dynamic>) {
                final normalized = ApiService.normalizeDriverRidePayload(
                  item,
                  fallbackDriverId: driverId,
                );
                final status =
                    normalized['status']?.toString().toLowerCase() ?? '';
                if (status == 'completed' || status == 'ended') {
                  final distStr = normalized['distance']?.toString() ?? '';
                  final cleanDist = distStr.replaceAll(RegExp(r'[^0-9.]'), '');
                  final val = double.tryParse(cleanDist);
                  if (val != null) {
                    totalDistanceKm += val;
                  }
                }
              }
            }
          }
        }
        updatePerformanceDistance(totalDistanceKm);
      }

      if (driverId.isEmpty) {
        _lastError = 'Driver ID is missing.';
        notifyListeners();
        return null;
      }

      // Fetch subscription from API
      final response = await _get(
        '${AppConstants.apiBaseUrl}/api/driver/$driverId/subscription',
      );
      final parsed = _decodeMap(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _subscription = SubscriptionModel.fromJson(parsed);
        _lastError = null;
      } else {
        if (_subscription != null) {
          final limit = _subscription!.kmLimit;
          if (limit != null) {
            _subscription = SubscriptionModel(
              status: totalDistanceKm >= limit
                  ? SubscriptionStatusType.blocked
                  : SubscriptionStatusType.active,
              kmRemaining: (limit - totalDistanceKm).clamp(0.0, limit),
              kmUsed: totalDistanceKm,
              kmLimit: limit,
              planName: _subscription!.planName,
              isUnlimitedActive: _subscription!.isUnlimitedActive,
              unlimitedExpiry: _subscription!.unlimitedExpiry,
            );
          } else {
            _subscription = SubscriptionModel(
              status: _subscription!.status,
              kmRemaining: _subscription!.kmRemaining,
              kmUsed: totalDistanceKm,
              kmLimit: null,
              planName: _subscription!.planName,
              isUnlimitedActive: _subscription!.isUnlimitedActive,
              unlimitedExpiry: _subscription!.unlimitedExpiry,
            );
          }
        } else {
          _subscription = SubscriptionModel(
            status: SubscriptionStatusType.unknown,
            kmRemaining: 0,
            kmUsed: totalDistanceKm,
            kmLimit: null,
            planName: 'No Subscription',
          );
        }
      }
      notifyListeners();
      return _subscription;
    } catch (e) {
      _lastError = 'Subscription fetch failed: $e';
      notifyListeners();
      return null;
    } finally {
      _loadingSubscription = false;
      notifyListeners();
    }
  }

  Future<List<SubscriptionPlanItem>> fetchPlans() async {
    _loadingPlans = true;
    _lastError = null;
    notifyListeners();

    try {
      final response = await _get(
        '${AppConstants.apiBaseUrl}/drivers/subscription-plans',
      );
      final parsed = _decodeMap(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final list = _extractPlanList(parsed);
        _plans = list
            .whereType<Map<String, dynamic>>()
            .map(SubscriptionPlanItem.fromJson)
            .where((p) => p.id.isNotEmpty && p.isActive)
            .toList();
        _lastError = null;
        notifyListeners();
        return _plans;
      }

      _lastError =
          _messageFromBody(parsed) ??
          'Failed to load plans (${response.statusCode}).';
      notifyListeners();
      return [];
    } on SocketException {
      _lastError = 'No internet connection.';
      notifyListeners();
      return [];
    } catch (e) {
      _lastError = 'Plans fetch failed: $e';
      notifyListeners();
      return [];
    } finally {
      _loadingPlans = false;
      notifyListeners();
    }
  }

  void _initRazorpay() {
    if (_razorpay != null) {
      debugPrint('Clearing existing Razorpay listeners before re-initializing');
      _razorpay!.clear();
    } else {
      _razorpay = Razorpay();
    }
    debugPrint('Registering Razorpay callbacks...');
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    debugPrint('RAZORPAY CALLBACK: EVENT_PAYMENT_SUCCESS triggered');
    debugPrint('  - Payment ID: ${response.paymentId}');
    debugPrint('  - Order ID: ${response.orderId}');
    debugPrint('  - Signature: ${response.signature}');

    final driverId = _pendingDriverId ?? '';
    final planId = _pendingPlanId ?? '';
    debugPrint('  - Internal state: driverId=$driverId, planId=$planId');

    if (driverId.isEmpty || planId.isEmpty) {
      _lastError = 'Payment succeeded but internal state is missing.';
      debugPrint('ERROR: $_lastError');
      _paymentCompleter?.complete(false);
      return;
    }

    try {
      final verifyBody = {
        'driverId': driverId,
        'planId': planId,
        'razorpay_order_id': response.orderId ?? '',
        'razorpay_payment_id': response.paymentId ?? '',
        'razorpay_signature': response.signature ?? '',
      };

      final verifyUrl =
          '${AppConstants.apiBaseUrl}/api/driver/subscription/verify-payment';
      debugPrint('Sending verify-payment request to $verifyUrl');
      debugPrint('Request Body: $verifyBody');

      final res = await _post(verifyUrl, verifyBody);

      debugPrint('VERIFY-PAYMENT RESPONSE STATUS: ${res.statusCode}');
      debugPrint('VERIFY-PAYMENT RESPONSE BODY: ${res.body}');

      final parsed = _decodeMap(res);
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          parsed['success'] == true) {
        _subscription = SubscriptionModel.fromJson(parsed);
        _lastError = null;
        notifyListeners();
        debugPrint('Payment verification SUCCESS');
        _paymentCompleter?.complete(true);
      } else {
        _lastError = _messageFromBody(parsed) ?? 'Payment verification failed.';
        debugPrint('ERROR: $_lastError');
        notifyListeners();
        _paymentCompleter?.complete(false);
      }
    } catch (e) {
      _lastError = 'Verification request failed: $e';
      debugPrint('ERROR: $_lastError');
      notifyListeners();
      _paymentCompleter?.complete(false);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint('RAZORPAY CALLBACK: EVENT_PAYMENT_ERROR triggered');
    debugPrint('  - Code: ${response.code}');
    debugPrint('  - Message: ${response.message}');
    _lastError = response.message ?? 'Payment failed or cancelled.';
    notifyListeners();
    _paymentCompleter?.complete(false);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('RAZORPAY CALLBACK: EVENT_EXTERNAL_WALLET triggered');
    debugPrint('  - Wallet Name: ${response.walletName}');
    _lastError = 'External wallets are not supported.';
    notifyListeners();
    _paymentCompleter?.complete(false);
  }

  Future<bool> requestPlan(String planId) async {
    if (planId.isEmpty) {
      _lastError = 'Plan ID is missing.';
      notifyListeners();
      return false;
    }

    try {
      final driverId = await SessionService.getDriverId() ?? '';
      if (driverId.isEmpty) {
        _lastError = 'Driver session not found.';
        notifyListeners();
        return false;
      }

      // Step 1: Create Order
      final orderBody = {'driverId': driverId, 'planId': planId};

      final response = await _post(
        '${AppConstants.apiBaseUrl}/api/driver/subscription/create-order',
        orderBody,
      );
      final parsed = _decodeMap(response);

      debugPrint('CREATE-ORDER REQUEST: $orderBody');
      debugPrint('CREATE-ORDER RESPONSE STATUS: ${response.statusCode}');
      debugPrint('CREATE-ORDER RESPONSE BODY: ${response.body}');

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          parsed['success'] != true) {
        _lastError =
            _messageFromBody(parsed) ?? 'Failed to create payment order.';
        notifyListeners();
        return false;
      }

      final orderId = parsed['orderId']?.toString() ?? '';
      final keyId = parsed['keyId']?.toString() ?? 'rzp_test_SznBROOyov9Oda';
      final amount = parsed['amount'] ?? 49900;
      final planName = parsed['planName']?.toString() ?? 'Subscription Plan';

      if (orderId.isEmpty) {
        _lastError = 'Order ID missing from response.';
        notifyListeners();
        return false;
      }

      // Initialize Razorpay client
      _initRazorpay();
      _pendingPlanId = planId;
      _pendingDriverId = driverId;

      _paymentCompleter = Completer<bool>();

      final options = {
        'key': keyId,
        'amount': amount,
        'name': 'ChalChalGaadi',
        'order_id': orderId,
        'description': planName,
        'prefill': {'contact': '', 'email': ''},
        'external': {
          'wallets': ['paytm'],
        },
      };

      _razorpay!.open(options);

      // Wait for Razorpay checkout callback to finish
      final success = await _paymentCompleter!.future;
      return success;
    } catch (e) {
      _lastError = 'Subscription checkout failed: $e';
      notifyListeners();
      return false;
    }
  }

  static List<dynamic> _extractPlanList(Map<String, dynamic> body) {
    for (final key in ['plans', 'subscriptionPlans', 'data', 'items']) {
      final value = body[key];
      if (value is List) return value;
    }
    if (body['data'] is List) return body['data'] as List;
    return const [];
  }

  static Map<String, dynamic> _decodeMap(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const {};
  }

  static String? _messageFromBody(Map<String, dynamic> body) {
    final message = body['message'];
    if (message is String && message.isNotEmpty) return message;
    final error = body['error'];
    if (error is String && error.isNotEmpty) return error;
    if (error != null) return error.toString();
    return null;
  }

  Future<Map<String, String>> _headers() async {
    final token = await SessionService.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> _get(String url) async {
    return http.get(Uri.parse(url), headers: await _headers());
  }

  Future<http.Response> _post(String url, Map<String, dynamic> body) async {
    return http.post(
      Uri.parse(url),
      headers: await _headers(),
      body: jsonEncode(body),
    );
  }
}
