import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../core/services/session_service.dart';
import '../models/category_model.dart';

/// Fetches ride categories (Bike, Auto, Sedan, etc.) from the backend.
///
/// Both user and driver apps share the same data — only the API endpoint
/// differs:
///   User   → GET /api/user/categories
///   Driver → GET /api/driver/categories
///
/// Usage:
///   final categories = await CategoryService.instance.fetchCategories();
///   final image      = CategoryService.instance.imageUrlForVehicleType('bike');
class CategoryService extends ChangeNotifier {
  CategoryService._();
  static final CategoryService instance = CategoryService._();

  List<CategoryModel> _categories = const [];
  bool _loading = false;
  String? _lastError;

  List<CategoryModel> get categories => List.unmodifiable(_categories);
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetch categories and cache them in memory.
  /// [role] should be either `'user'` or `'driver'` (default: auto-detect from session).
  Future<List<CategoryModel>> fetchCategories({String? role}) async {
    if (_loading) return _categories;

    _loading = true;
    _lastError = null;
    notifyListeners();

    try {
      final resolvedRole = role ?? await _resolveRole();
      // New endpoints: /api/user/categories and /api/driver/categories
      final url = resolvedRole == 'driver'
          ? '${AppConstants.apiBaseUrl}/api/driver/categories'
          : '${AppConstants.apiBaseUrl}/api/user/categories';

      debugPrint('[CategoryService] GET $url');

      final response = await http
          .get(Uri.parse(url), headers: await _buildHeaders())
          .timeout(const Duration(seconds: 15));

      debugPrint('[CategoryService] Status: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final parsed = _decodeMap(response);
        final rawList = _extractList(parsed);
        _categories = rawList
            .whereType<Map>()
            .map((e) => CategoryModel.fromJson(Map<String, dynamic>.from(e)))
            .where((c) => c.key.isNotEmpty)
            .toList();

        debugPrint('[CategoryService] Loaded ${_categories.length} categories');
        _lastError = null;
      } else {
        _lastError = 'Categories fetch failed (${response.statusCode}).';
        debugPrint('[CategoryService] Error: $_lastError');
      }
    } on SocketException {
      _lastError = 'No internet connection.';
    } on Exception catch (e) {
      _lastError = 'Categories fetch failed: $e';
      debugPrint('[CategoryService] Exception: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }

    return _categories;
  }

  /// Returns the [CategoryModel] whose `key` matches [vehicleType].
  ///
  /// Matching priority:
  ///  1. Exact lowercase key match
  ///  2. Alias normalisation (e.g. "sedan ac" → "sedan", "suv" variants)
  ///  3. Contains partial match
  ///
  /// Returns `null` if not found or list is empty.
  CategoryModel? getByVehicleType(String vehicleType) {
    if (vehicleType.isEmpty || _categories.isEmpty) return null;

    final key = vehicleType.toLowerCase().trim();

    // 1. Exact match
    try {
      return _categories.firstWhere((c) => c.key == key);
    } catch (_) {}

    // 2. Alias normalisation — map common app-side names to API key variants
    final aliases = _buildAliases(key);
    for (final alias in aliases) {
      try {
        final match = _categories.firstWhere(
          (c) => c.key == alias || c.name.toLowerCase() == alias,
        );
        return match;
      } catch (_) {}
    }

    // 3. Partial contains
    try {
      return _categories.firstWhere(
        (c) => c.key.contains(key) || key.contains(c.key),
      );
    } catch (_) {}

    return null;
  }

  /// Builds a list of alias keys for common vehicle type name variants.
  static List<String> _buildAliases(String key) {
    // Normalise compound names to simple keys
    if (key.contains('sedan')) return ['sedan', 'sedan ac', 'luxury'];
    if (key.contains('suv')) return ['suv', 'xuv', 'innova'];
    if (key.contains('luxury') || key.contains('premium')) {
      return ['luxury', 'sedan ac', 'sedan'];
    }
    if (key.contains('auto') || key.contains('rick')) {
      return ['auto', 'auto rickshaw'];
    }
    if (key.contains('bike') || key.contains('moto')) return ['bike', 'moto'];
    if (key.contains('ev') || key.contains('electric')) {
      return ['ev', 'electric'];
    }
    if (key == 'car') return ['car', 'sedan'];
    return [];
  }

  /// Full image URL for a given vehicle type key.
  /// Returns empty string if not found.
  String imageUrlForVehicleType(String vehicleType) {
    final cat = getByVehicleType(vehicleType);
    if (cat == null) return '';
    return cat.fullImageUrl(AppConstants.apiBaseUrl);
  }

  /// Fetch categories only if not already loaded.
  Future<List<CategoryModel>> getOrFetch({String? role}) async {
    if (_categories.isNotEmpty) return _categories;
    return fetchCategories(role: role);
  }

  /// Clear cached categories (e.g. on logout).
  void clear() {
    _categories = const [];
    _lastError = null;
    notifyListeners();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<String> _resolveRole() async {
    final role = await SessionService.getRole();
    return role ?? 'user';
  }

  Future<Map<String, String>> _buildHeaders() async {
    final token = await SessionService.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static List<dynamic> _extractList(Map<String, dynamic> body) {
    for (final key in ['categories', 'data', 'items', 'results']) {
      final value = body[key];
      if (value is List) return value;
    }
    return const [];
  }

  static Map<String, dynamic> _decodeMap(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const {};
  }
}
