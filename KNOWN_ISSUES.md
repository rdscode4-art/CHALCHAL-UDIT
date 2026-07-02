# Known Issues

This document tracks current known issues and workarounds in the Chal Chal Gadi (RideGo) application.

## 1. Rendering Jank on Android 16 (Motorola Devices)
**Issue:** Some users experience rendering freezes, stuttering, or UI jank on devices running Android 16, specifically Motorola handsets.

**Workaround:** 
The issue stems from the new Impeller rendering engine.
For local debugging, run the app without Impeller:
```bash
flutter run --no-enable-impeller
```
Alternatively, profile mode can help identify specific bottlenecks:
```bash
flutter run --profile
```
*Note: Hardware acceleration is already explicitly enabled in `AndroidManifest.xml` to mitigate this.*
