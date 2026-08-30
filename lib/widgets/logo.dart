// SQL Pulse — brand logo (data cylinder + lime pulse line) as a CustomPainter.
import 'package:flutter/material.dart';

class SpLogo extends StatelessWidget {
  final double size;
  final double? radius;
  const SpLogo({super.key, this.size = 40, this.radius});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(radius ?? size * 0.28)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double radius;
  _LogoPainter(this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final k = s / 512.0; // design is 512x512
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF5772FF), Color(0xFF2E44D6)],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rrect, bg);

    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // data cylinder (ellipse top + sides + bottom curve)
    final cx = 256 * k, cyTop = 168 * k, rx = 112 * k, ry = 44 * k;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cyTop), width: rx * 2, height: ry * 2), white);
    canvas.drawLine(Offset(144 * k, 168 * k), Offset(144 * k, 344 * k), white);
    canvas.drawLine(Offset(368 * k, 168 * k), Offset(368 * k, 344 * k), white);
    final bottom = Path()
      ..moveTo(144 * k, 344 * k)
      ..arcToPoint(Offset(368 * k, 344 * k), radius: Radius.elliptical(112 * k, 44 * k), clockwise: false);
    canvas.drawPath(bottom, white);

    // lime pulse line
    final pulse = Paint()
      ..color = const Color(0xFFC2F042)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = Path()
      ..moveTo(118 * k, 262 * k)
      ..lineTo(214 * k, 262 * k)
      ..lineTo(240 * k, 210 * k)
      ..lineTo(286 * k, 322 * k)
      ..lineTo(312 * k, 262 * k)
      ..lineTo(394 * k, 262 * k);
    canvas.drawPath(p, pulse);
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => oldDelegate.radius != radius;
}
