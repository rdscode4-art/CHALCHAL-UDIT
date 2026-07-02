import 'package:flutter/material.dart';

/// Renders the new Chal Chal Gadi brand mark as a pure Flutter widget.
/// The design matches the requested app icon style with:
///  - black circular background
///  - yellow "Chal Chal" lines
///  - white angled "Gadi" text
///  - horizontal traffic-light pill with red, yellow, green dots
///
/// [size] controls the diameter of the logo circle.
class ChalChalGadiLogo extends StatelessWidget {
  final double size;

  const ChalChalGadiLogo({super.key, this.size = 160});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset('assets/logo2.png', fit: BoxFit.contain),
    );
  }
}

/// Compact inline version — uses the same brand colours in a smaller layout.
class ChalChalGadiLogoInline extends StatelessWidget {
  final double height;
  final Color textColor;

  const ChalChalGadiLogoInline({
    super.key,
    this.height = 36,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final dotSize = height * 0.28;
    final fontSize = height * 0.55;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Chal Chal',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: const Color(0xFFFDD835),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(width: 8),
        Transform.rotate(
          angle: -0.08,
          child: Text(
            'Gadi',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: textColor,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Row(
          children: [
            _dot(const Color(0xFFE53935), dotSize),
            SizedBox(width: dotSize * 0.35),
            _dot(const Color(0xFFFDD835), dotSize),
            SizedBox(width: dotSize * 0.35),
            _dot(const Color(0xFF43A047), dotSize),
          ],
        ),
      ],
    );
  }

  Widget _dot(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
