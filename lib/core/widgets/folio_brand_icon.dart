import 'package:flutter/material.dart';

/// Vector brand icon for Folio (Japanese minimalist 3-facet Tsuru origami).
///
/// Mirrors `assets/branding/folio-icon.svg` with identical normalized
/// coordinates so it renders razor-sharp at any DPI without raster assets.
class FolioBrandIcon extends StatelessWidget {
  const FolioBrandIcon({
    super.key,
    this.size = 32,
    this.borderRadius,
    this.backgroundColor = const Color(0xFFF5F3EE),
    this.inkColor = const Color(0xFF161618),
    this.borderColor = const Color(0xFFDCD9D0),
    this.showBackground = true,
  });

  final double size;
  final double? borderRadius;
  final Color backgroundColor;
  final Color inkColor;
  final Color? borderColor;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? (size * 0.23);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FolioTsuruPainter(
          radius: radius,
          backgroundColor: backgroundColor,
          inkColor: inkColor,
          borderColor: borderColor,
          showBackground: showBackground,
        ),
      ),
    );
  }
}

class _FolioTsuruPainter extends CustomPainter {
  const _FolioTsuruPainter({
    required this.radius,
    required this.backgroundColor,
    required this.inkColor,
    required this.borderColor,
    required this.showBackground,
  });

  final double radius;
  final Color backgroundColor;
  final Color inkColor;
  final Color? borderColor;
  final bool showBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 1024.0;
    final sy = size.height / 1024.0;

    if (showBackground) {
      final rrect = RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      );
      canvas.drawRRect(rrect, Paint()..color = backgroundColor);
      if (borderColor != null) {
        canvas.drawRRect(
          rrect.deflate(0.5),
          Paint()
            ..color = borderColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      }
    }

    final inkPaint = Paint()
      ..color = inkColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    void drawPoly(List<Offset> pts) {
      final path = Path()..moveTo(pts.first.dx * sx, pts.first.dy * sy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx * sx, pts[i].dy * sy);
      }
      path.close();
      canvas.drawPath(path, inkPaint);
    }

    // 1. Main tall origami wing
    drawPoly(const [
      Offset(311.2, 662.6),
      Offset(565.8, 271.8),
      Offset(522.8, 565.8),
    ]);
    // 2. Lower base fold
    drawPoly(const [
      Offset(329.1, 691.3),
      Offset(537.1, 594.5),
      Offset(694.9, 691.3),
    ]);
    // 3. Upper right wing/head facet
    drawPoly(const [
      Offset(590.9, 307.6),
      Offset(745.1, 422.4),
      Offset(551.4, 544.3),
    ]);
  }

  @override
  bool shouldRepaint(covariant _FolioTsuruPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.inkColor != inkColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.showBackground != showBackground;
  }
}
