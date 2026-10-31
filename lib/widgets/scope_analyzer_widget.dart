import 'package:flutter/material.dart';
import '../services/pipeline_engine.dart';

/// 4대 전문 스코프 모니터 (SemiDarktable 정밀 호환)
/// 1. 히스토그램 (Histogram)
/// 2. 웨이브폼 (Waveform Monitor)
/// 3. RGB 파레이드 (RGB Parade)
/// 4. 8밴드 컬러 에너지 (8-Band Color Graph)
class ScopeAnalyzerWidget extends StatefulWidget {
  final ScopeAnalysisResult? scopeData;

  const ScopeAnalyzerWidget({super.key, this.scopeData});

  @override
  State<ScopeAnalyzerWidget> createState() => _ScopeAnalyzerWidgetState();
}

class _ScopeAnalyzerWidgetState extends State<ScopeAnalyzerWidget> {
  String _mode = 'histogram'; // 'histogram', 'waveform', 'parade', '8-band'

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: Column(
        children: [
          // 스코프 모드 선택 헤더 바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF1B1B1B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Row(
              children: [
                _modeButton('histogram', '히스토그램'),
                const SizedBox(width: 4),
                _modeButton('waveform', '웨이브폼'),
                const SizedBox(width: 4),
                _modeButton('parade', '파레이드'),
                const SizedBox(width: 4),
                _modeButton('8-band', '8-밴드'),
              ],
            ),
          ),

          // 스코프 그래픽 캔버스 (높이 130px)
          SizedBox(
            height: 125,
            width: double.infinity,
            child: CustomPaint(
              painter: _ScopePainter(
                mode: _mode,
                data: widget.scopeData,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(String id, String label) {
    final isSelected = _mode == id;
    return GestureDetector(
      onTap: () => setState(() => _mode = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF332512) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: isSelected ? Border.all(color: const Color(0xFFDCA353)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFFDCA353) : Colors.grey[400],
          ),
        ),
      ),
    );
  }
}

class _ScopePainter extends CustomPainter {
  final String mode;
  final ScopeAnalysisResult? data;

  _ScopePainter({required this.mode, required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data == null) return;

    if (mode == 'histogram') {
      _drawHistogram(canvas, size);
    } else if (mode == 'waveform') {
      _drawWaveform(canvas, size);
    } else if (mode == 'parade') {
      _drawParade(canvas, size);
    } else if (mode == '8-band') {
      _draw8Band(canvas, size);
    }
  }

  void _drawHistogram(Canvas canvas, Size size) {
    final binsR = data!.rBins;
    final binsG = data!.gBins;
    final binsB = data!.bBins;
    final binsL = data!.lumaBins;
    final maxVal = data!.maxBinValue.toDouble();
    if (maxVal <= 0) return;

    final stepX = size.width / 256.0;

    void drawCurve(List<int> bins, Color col, {bool fill = true}) {
      final path = Path();
      path.moveTo(0, size.height);
      for (int i = 0; i < 256; i++) {
        final x = i * stepX;
        final y = size.height - (bins[i] / maxVal * size.height * 0.95);
        path.lineTo(x, y);
      }
      if (fill) {
        path.lineTo(size.width, size.height);
        path.close();
        canvas.drawPath(path, Paint()..color = col..style = PaintingStyle.fill);
      } else {
        canvas.drawPath(path, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 1.0);
      }
    }

    drawCurve(binsR, const Color(0x66FF3B30));
    drawCurve(binsG, const Color(0x6634C759));
    drawCurve(binsB, const Color(0x66007AFF));
    drawCurve(binsL, const Color(0x99FFFFFF), fill: false);
  }

  void _drawWaveform(Canvas canvas, Size size) {
    final points = data!.waveformPoints;
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0x334CD964)
      ..strokeWidth = 1.0;

    for (int i = 0; i < points.length; i += 2) {
      final nx = points[i];
      final ny = points[i + 1];
      canvas.drawCircle(Offset(nx * size.width, (1.0 - ny) * size.height), 0.7, paint);
    }
  }

  void _drawParade(Canvas canvas, Size size) {
    final points = data!.waveformPoints;
    if (points.isEmpty) return;

    final segW = size.width / 3.0;
    final pR = Paint()..color = const Color(0x55FF3B30)..strokeWidth = 1.0;
    final pG = Paint()..color = const Color(0x5534C759)..strokeWidth = 1.0;
    final pB = Paint()..color = const Color(0x55007AFF)..strokeWidth = 1.0;

    for (int i = 0; i < points.length; i += 2) {
      final nx = points[i];
      final ny = points[i + 1];
      final y = (1.0 - ny) * size.height;

      canvas.drawCircle(Offset(nx * segW, y), 0.7, pR);
      canvas.drawCircle(Offset(segW + nx * segW, y), 0.7, pG);
      canvas.drawCircle(Offset(segW * 2 + nx * segW, y), 0.7, pB);
    }
  }

  void _draw8Band(Canvas canvas, Size size) {
    final levels = data!.eightBandLevels;
    final names = ['R', 'O', 'Y', 'G', 'C', 'B', 'P', 'M'];
    final colors = [
      const Color(0xFFFF3B30),
      const Color(0xFFFF9500),
      const Color(0xFFFFCC00),
      const Color(0xFF34C759),
      const Color(0xFF00C7BE),
      const Color(0xFF007AFF),
      const Color(0xFF5856D6),
      const Color(0xFFAF52DE),
    ];

    final colW = size.width / 8.0;
    final chartH = size.height - 20;

    for (int i = 0; i < 8; i++) {
      final x = i * colW + 4;
      final w = colW - 8;
      final val = (i < levels.length ? levels[i] : 0.0).clamp(0.0, 1.0);
      final barH = val * chartH;
      final y = chartH - barH;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, barH), const Radius.circular(2)),
        Paint()..color = colors[i],
      );

      final tp = TextPainter(
        text: TextSpan(
          text: names[i],
          style: TextStyle(color: colors[i], fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + (w - tp.width) / 2, chartH + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _ScopePainter oldDelegate) => true;
}
