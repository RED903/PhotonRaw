import 'package:flutter/material.dart';
import '../services/pipeline_engine.dart';

/// 실시간 RGB / Luma 히스토그램 스코프 위젯
class HistogramWidget extends StatelessWidget {
  final HistogramData? data;

  const HistogramWidget({super.key, this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Stack(
          children: [
            // 히스토그램 커스텀 페인터
            Positioned.fill(
              child: CustomPaint(
                painter: _HistogramPainter(data: data),
              ),
            ),
            // 채널 가이드라인 및 라벨
            Positioned(
              left: 6,
              top: 4,
              child: Row(
                children: [
                  _channelBadge('R', const Color(0xFFFF5252)),
                  const SizedBox(width: 4),
                  _channelBadge('G', const Color(0xFF69F0AE)),
                  const SizedBox(width: 4),
                  _channelBadge('B', const Color(0xFF448AFF)),
                  const SizedBox(width: 4),
                  _channelBadge('L', Colors.white70),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final HistogramData? data;

  _HistogramPainter({this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data == null || data!.maxBinValue <= 0) return;

    final width = size.width;
    final height = size.height;
    final binWidth = width / 256.0;
    final maxVal = data!.maxBinValue.toDouble();

    // 1. 그리드 가이드라인 (25%, 50%, 75% 톤 분할)
    final gridPaint = Paint()
      ..color = const Color(0xFF222222)
      ..strokeWidth = 1.0;
    for (int i = 1; i <= 3; i++) {
      final x = width * (i / 4.0);
      canvas.drawLine(Offset(x, 0), Offset(x, height), gridPaint);
    }

    // 채널별 경로 그리기
    _drawChannel(canvas, size, data!.rBins, maxVal, binWidth, const Color(0x66FF5252));
    _drawChannel(canvas, size, data!.gBins, maxVal, binWidth, const Color(0x6669F0AE));
    _drawChannel(canvas, size, data!.bBins, maxVal, binWidth, const Color(0x66448AFF));
    _drawChannel(canvas, size, data!.lumaBins, maxVal, binWidth, const Color(0x99FFFFFF), isLineOnly: true);
  }

  void _drawChannel(
    Canvas canvas,
    Size size,
    List<int> bins,
    double maxVal,
    double binWidth,
    Color color, {
    bool isLineOnly = false,
  }) {
    final path = Path();
    path.moveTo(0, size.height);

    for (int i = 0; i < 256; i++) {
      final x = i * binWidth;
      // 대수(Log) 스케일로 압축하여 피크와 섀도우를 자연스럽게 시각화
      final normalized = bins[i] / maxVal;
      final y = size.height - (normalized * size.height * 0.95);
      path.lineTo(x, y);
    }

    if (!isLineOnly) {
      path.lineTo(size.width, size.height);
      path.close();
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
    } else {
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) => true;
}
