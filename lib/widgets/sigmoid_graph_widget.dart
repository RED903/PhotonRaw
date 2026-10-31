import 'dart:math' as math;
import 'package:flutter/material.dart';

/// SemiDarktable의 SigmoidGraphWidget 1:1 이식
/// - pipeline_core.dart의 시그모이드 수식과 100% 동일한 실시간 S-Curve 시각화
/// - 더블클릭 시 시그모이드 파라미터 기본값 초기화
class SigmoidGraphWidget extends StatelessWidget {
  final double contrast;
  final double skew;
  final double shoulder;
  final double toe;
  final VoidCallback? onDoubleTapReset;

  const SigmoidGraphWidget({
    super.key,
    required this.contrast,
    required this.skew,
    required this.shoulder,
    required this.toe,
    this.onDoubleTapReset,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTapReset,
      child: Tooltip(
        message: '더블클릭하여 시그모이드 곡선 초기화',
        child: Container(
          width: double.infinity,
          height: 100,
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF181818),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF363636)),
          ),
          child: CustomPaint(
            painter: _SigmoidPainter(
              contrast: contrast,
              skew: skew,
              shoulder: shoulder,
              toe: toe,
            ),
          ),
        ),
      ),
    );
  }
}

class _SigmoidPainter extends CustomPainter {
  final double contrast;
  final double skew;
  final double shoulder;
  final double toe;

  _SigmoidPainter({
    required this.contrast,
    required this.skew,
    required this.shoulder,
    required this.toe,
  });

  double _eval(double c) {
    if ((contrast - 1.0).abs() < 1e-3 &&
        skew.abs() < 1e-3 &&
        shoulder.abs() < 1e-3 &&
        toe.abs() < 1e-3) {
      return c;
    }
    final sigK = math.max(0.1, 4.0 * (contrast - 1.0) + 1.0);
    final sigMid = 0.5 + skew * 0.25;
    final sigS0 = 1.0 / (1.0 + math.exp(sigK * sigMid));
    final sigS1 = 1.0 / (1.0 + math.exp(-sigK * (1.0 - sigMid)));
    final sigDenom = math.max(0.0001, sigS1 - sigS0);
    final shExp = 1.0 - shoulder * 0.4;
    final toeExp = 1.0 + toe * 0.4;

    final raw = 1.0 / (1.0 + math.exp(-sigK * (c - sigMid)));
    var s = ((raw - sigS0) / sigDenom).clamp(0.0, 1.0).toDouble();
    if (shoulder != 0) {
      s = 0.5 * s + 0.5 * math.pow(s, shExp).toDouble();
    }
    if (toe != 0) {
      s = 0.5 * s + 0.5 * math.pow(s, toeExp).toDouble();
    }
    return s.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    final w = (size.width - pad * 2).clamp(1.0, 10000.0);
    final h = (size.height - pad * 2).clamp(1.0, 10000.0);

    final gridPaint = Paint()
      ..color = const Color(0xFF292929)
      ..strokeWidth = 1.0;
    for (int i = 1; i < 4; i++) {
      final gx = pad + w * (i / 4.0);
      final gy = pad + h * (i / 4.0);
      canvas.drawLine(Offset(gx, pad), Offset(gx, pad + h), gridPaint);
      canvas.drawLine(Offset(pad, gy), Offset(pad + w, gy), gridPaint);
    }

    final diagPaint = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(pad, pad + h), Offset(pad + w, pad), diagPaint);

    final path = Path();
    const steps = 80;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final y = _eval(t);
      final px = pad + t * w;
      final py = pad + (1.0 - y) * h;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    final curvePaint = Paint()
      ..color = const Color(0xFFE8A838)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, curvePaint);
  }

  @override
  bool shouldRepaint(covariant _SigmoidPainter oldDelegate) =>
      oldDelegate.contrast != contrast ||
      oldDelegate.skew != skew ||
      oldDelegate.shoulder != shoulder ||
      oldDelegate.toe != toe;
}
