import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class DriverBubbleOverlay extends StatelessWidget {
  const DriverBubbleOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {
          // If you want to open the main app on tap, uncomment this:
          FlutterOverlayWindow.shareData('open_app');
        },
        child: Container(
          width: 80,
          height: 80,
          child: Image.asset(
            'assets/logo.png',
            width: 80,
            height: 80,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
