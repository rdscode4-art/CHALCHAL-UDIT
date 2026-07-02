import 'package:flutter/material.dart';

class AppTheme {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(
    ThemeMode.system,
  );

  static void toggleMode() {
    themeMode.value = themeMode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  static const String darkMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#14232d"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#172d40"},{"visibility":"on"},{"weight":0.5}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#c2d7ff"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#8fb3c3"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#112a1e"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1f2c3d"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ba5b4"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c5a75"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#02102f"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#5f86d7"}]}
]''';
}
