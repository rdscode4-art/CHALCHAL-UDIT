# ridego

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Troubleshooting Android 16 / Motorola

If you encounter rendering freezes or UI jank on Android 16, especially on Motorola devices, try:

- `flutter run --no-enable-impeller`
- `flutter run --profile`

This app also enables `android:hardwareAccelerated="true"` in `android/app/src/main/AndroidManifest.xml` to improve rendering performance.
