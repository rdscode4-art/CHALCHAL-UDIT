import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/services.dart' show rootBundle, ByteData;

import '../constants/app_constants.dart';

/// Centralized map utilities: polyline decoder, Directions API, ETA,
/// distance calculation, and custom marker helpers.
class MapUtils {
  MapUtils._();

  // ── Google Maps API key (unified across the whole app) ─────────────────
  static const String mapsApiKey = AppConstants.mapsApiKey;

  // ── Emoji marker cache (static, shared across all screens) ─────────────
  static final Map<String, BitmapDescriptor> _markerCache = {};

  // ──────────────────────────────────────────────────────────────────────
  // 1. Polyline decoder
  // ──────────────────────────────────────────────────────────────────────
  /// Decodes a Google Maps encoded polyline string into a list of [LatLng].
  static List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int result = 0;
      int shift = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  // ──────────────────────────────────────────────────────────────────────
  // 2. Google Directions API
  // ──────────────────────────────────────────────────────────────────────
  /// Fetches a route from [origin] to [destination] using the Google
  /// Directions API.  Returns a [DirectionsResult] with decoded polyline
  /// points, distance in km and duration in minutes.
  ///
  /// Falls back to a straight-line path on failure.
  static Future<DirectionsResult> getDirections({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=$mapsApiKey',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0] as Map<String, dynamic>;
          final legs = route['legs'] as List<dynamic>?;

          double distKm = 0;
          double durMin = 0;
          if (legs != null && legs.isNotEmpty) {
            final leg = legs[0] as Map<String, dynamic>;
            distKm = (leg['distance']['value'] as num) / 1000;
            durMin = (leg['duration']['value'] as num) / 60;
          }

          final poly = route['overview_polyline']?['points'] as String? ?? '';
          final points = poly.isNotEmpty
              ? decodePolyline(poly)
              : [origin, destination];

          return DirectionsResult(
            points: points,
            distanceKm: distKm,
            durationMin: durMin,
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ [MapUtils] Directions API error: $e');
    }
    // Fallback: straight line
    return DirectionsResult(
      points: [origin, destination],
      distanceKm: haversineKm(origin, destination),
      durationMin: haversineKm(origin, destination) * 2.5,
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // 3. Geocoding
  // ──────────────────────────────────────────────────────────────────────
  /// Geocodes a place-name or address to [LatLng] using the Google
  /// Geocoding API.  Returns `null` on failure.
  static Future<LatLng?> geocode(String address) async {
    if (address.trim().isEmpty) return null;
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': address,
        'key': mapsApiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          final loc =
              results[0]['geometry']['location'] as Map<String, dynamic>;
          return LatLng(loc['lat'] as double, loc['lng'] as double);
        }
      }
    } catch (e) {
      debugPrint('⚠️ [MapUtils] Geocode error for "$address": $e');
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────────────
  // 4. Distance utilities
  // ──────────────────────────────────────────────────────────────────────
  /// Haversine great-circle distance in kilometres between two [LatLng].
  static double haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(a.latitude)) *
            math.cos(_toRad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;

  /// ETA string from driver location to [dest] using straight-line speed.
  static String etaString(LatLng driverPos, LatLng dest) {
    final km = haversineKm(driverPos, dest);
    // Assume ~20 km/h average in city traffic
    final minutes = (km / 20.0 * 60).round().clamp(1, 999);
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  // ──────────────────────────────────────────────────────────────────────
  // 5. Camera helpers
  // ──────────────────────────────────────────────────────────────────────
  /// Animates [controller] to fit all [points] in view with [padding].
  static void fitBounds(
    GoogleMapController controller,
    List<LatLng> points, {
    double padding = 60,
  }) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    try {
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          padding,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ [MapUtils] fitBounds error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // 6. Custom emoji markers
  // ──────────────────────────────────────────────────────────────────────
  /// Returns a [BitmapDescriptor] containing [emoji] rendered at [size].
  /// Results are cached so each emoji is only rendered once.
  static Future<BitmapDescriptor> emojiMarker(
    String emoji, {
    double size = 80,
  }) async {
    final cacheKey = '${emoji}_$size';
    if (_markerCache.containsKey(cacheKey)) return _markerCache[cacheKey]!;

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: emoji,
          style: TextStyle(fontSize: size),
        )
        ..layout();
      painter.paint(canvas, Offset.zero);
      final img = await recorder.endRecording().toImage(
        painter.width.toInt(),
        painter.height.toInt(),
      );
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        final descriptor = BitmapDescriptor.fromBytes(
          bytes.buffer.asUint8List(),
        );
        _markerCache[cacheKey] = descriptor;
        return descriptor;
      }
    } catch (e) {
      debugPrint('⚠️ [MapUtils] emojiMarker error: $e');
    }
    return BitmapDescriptor.defaultMarker;
  }

  /// Returns a vehicle-type emoji for a given [vehicleType] string.
  static String vehicleEmoji(String vehicleType) {
    final t = vehicleType.toLowerCase();
    if (t.contains('bike') || t.contains('moto')) return '🛵';
    if (t.contains('auto') || t.contains('rickshaw') || t.contains('tuk')) {
      return '🛺';
    }
    if (t.contains('truck') || t.contains('suv')) return '🚙';
    return '🚗';
  }

  /// Calculates the bearing between two coordinates in degrees.
  static double calculateBearing(LatLng startPoint, LatLng endPoint) {
    final startLat = startPoint.latitude * math.pi / 180;
    final startLng = startPoint.longitude * math.pi / 180;
    final endLat = endPoint.latitude * math.pi / 180;
    final endLng = endPoint.longitude * math.pi / 180;

    final dLng = endLng - startLng;

    final y = math.sin(dLng) * math.cos(endLat);
    final x = math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(dLng);

    final angle = math.atan2(y, x);
    return (angle * 180 / math.pi + 360) % 360;
  }

  static final Map<String, BitmapDescriptor> _vehicle3DMarkers = {};

  /// Returns the premium 3D vehicle marker icon according to the vehicle type.
  static Future<BitmapDescriptor> get3DVehicleMarkerForType(String vehicleType) async {
    final t = vehicleType.toLowerCase();
    String assetName = 'auto_3d.png'; // default fallback
    int targetWidth = 65; // default target width in physical pixels
    
    if (t.contains('bike') || t.contains('moto') || t == '2-wheeler') {
      assetName = 'bike_3d.png';
      targetWidth = 45; // Bike is thinner
    } else if (t.contains('auto') || t.contains('rickshaw') || t.contains('tuk')) {
      assetName = 'auto_3d.png';
      targetWidth = 65;
    } else if (t == 'ev' || t.contains('electric') || t.contains('green')) {
      assetName = 'ev_3d.png';
      targetWidth = 70;
    } else if (t.contains('suv') || t.contains('truck') || t.contains('jeep')) {
      assetName = 'suv_3d.png';
      targetWidth = 75;
    } else if (t.contains('sedan') || t.contains('luxury') || t.contains('car') || t.contains('cab')) {
      assetName = 'sedan_3d.png';
      targetWidth = 70;
    }

    final cacheKey = '${assetName}_$targetWidth';
    if (_vehicle3DMarkers.containsKey(cacheKey)) {
      return _vehicle3DMarkers[cacheKey]!;
    }

    try {
      final ByteData data = await rootBundle.load('assets/$assetName');
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: targetWidth,
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? bytes = await fi.image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        final marker = BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
        _vehicle3DMarkers[cacheKey] = marker;
        return marker;
      }
    } catch (e) {
      debugPrint('⚠️ [MapUtils] Error loading/resizing 3D marker asset assets/$assetName: $e');
    }

    // Fallback using original asset load
    try {
      final marker = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(35, 35)),
        'assets/$assetName',
      );
      _vehicle3DMarkers[cacheKey] = marker;
      return marker;
    } catch (e) {
      if (assetName != 'auto_3d.png') {
        return get3DVehicleMarkerForType('auto');
      }
      return BitmapDescriptor.defaultMarker;
    }
  }

  /// Returns the premium 3D auto vehicle marker icon.
  static Future<BitmapDescriptor> get3DVehicleMarker() async {
    return get3DVehicleMarkerForType('auto');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// Result returned by [MapUtils.getDirections].
// ─────────────────────────────────────────────────────────────────────────────
class DirectionsResult {
  final List<LatLng> points;
  final double distanceKm;
  final double durationMin;

  const DirectionsResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });

  String get distanceText {
    if (distanceKm < 1) return '${(distanceKm * 1000).round()} m';
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  String get durationText {
    final min = durationMin.round();
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
