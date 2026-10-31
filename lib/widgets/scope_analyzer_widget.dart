import 'package:flutter/material.dart';
import '../services/scopes.dart';

/// SemiDarktable의 ScopeWidget 1:1 이식 (순수 CustomPainter 벡터/그리드 렌더링)
/// - GPU 텍스처(ui.Image) 생성 및 dispose()를 전혀 사용하지 않아 창 크기 변경/슬라이더 조작 시 네이티브 크래시 원천 차단
/// - 4개 분석 모드 탭: Waveform, Parade, Histogram, 8-Band
class ScopeAnalyzerWidget extends StatefulWidget {
  final ScopeData? scopeData;
  final bool collapsible;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const ScopeAnalyzerWidget({
    super.key,
    required this.scopeData,
    this.collapsible = false,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  @override
  State<ScopeAnalyzerWidget> createState() => _ScopeAnalyzerWidgetState();
}

class _ScopeAnalyzerWidgetState extends State<ScopeAnalyzerWidget> {
  String _mode = 'waveform'; // 'waveform', 'parade', 'histogram', 'bands'

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF343434)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4개 스코프 모드 전환 버튼 + (세로 긴 모바일 화면에서) 열고 닫기 토글 버튼
          SizedBox(
            height: 24,
            child: Row(
              children: [
                if (widget.collapsible)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: widget.onToggleCollapse,
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFF444444)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.collapsed ? '▶ 파형 열기' : '▼ 파형 닫기',
                              style: const TextStyle(
                                fontSize: 10.0,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE8A838),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                for (final m in [
                  ('waveform', 'Waveform'),
                  ('parade', 'Parade'),
                  ('histogram', 'Histogram'),
                  ('bands', '8-Band'),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        onTap: () {
                          setState(() => _mode = m.$1);
                          if (widget.collapsible && widget.collapsed) {
                            widget.onToggleCollapse?.call();
                          }
                        },
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _mode == m.$1 && !widget.collapsed
                                ? const Color(0xFF3E3524)
                                : const Color(0xFF181818),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: _mode == m.$1 && !widget.collapsed
                                  ? const Color(0xFFE8A838)
                                  : const Color(0xFF333333),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              m.$2,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: _mode == m.$1 && !widget.collapsed
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _mode == m.$1 && !widget.collapsed
                                    ? const Color(0xFFE8A838)
                                    : const Color(0xFF999999),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!widget.collapsed) ...[
            const SizedBox(height: 6),
            // 스코프 표시 캔버스
            Container(
              height: 118,
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF2D2D2D)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: _buildScopeBody(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScopeBody() {
    final data = widget.scopeData;
    if (data == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            '이미지를 불러오면 실시간 파형/히스토그램이 표시됩니다',
            style: TextStyle(fontSize: 10.5, color: Color(0xFF666666)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_mode == 'bands') {
      return CustomPaint(
        size: const Size(double.infinity, 118),
        painter: _EightBandPainter(levels: data.bandLevels),
      );
    }

    return CustomPaint(
      size: const Size(double.infinity, 118),
      painter: _DirectScopePainter(
        data: data,
        mode: _mode,
      ),
    );
  }
}

class _DirectScopePainter extends CustomPainter {
  final ScopeData data;
  final String mode;

  _DirectScopePainter({
    required this.data,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 4 || size.height <= 4) return;

    // 배경 격자선
    final gridPaint = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 0.8;
    for (int i = 1; i < 4; i++) {
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (mode == 'histogram') {
      _paintHistogram(canvas, size);
    } else if (mode == 'parade') {
      _paintParade(canvas, size, gridPaint);
    } else {
      _paintWaveform(canvas, size);
    }
  }

  void _paintHistogram(Canvas canvas, Size size) {
    final channels = [
      (data.histR, const Color(0xFFFF4444)),
      (data.histG, const Color(0xFF44DD55)),
      (data.histB, const Color(0xFF4488FF)),
    ];

    for (final ch in channels) {
      final bins = ch.$1;
      final color = ch.$2;
      final len = bins.length;
      if (len < 2) continue;

      final fillPath = Path()..moveTo(0, size.height);
      final linePath = Path();
      for (int i = 0; i < len; i++) {
        final x = (i / (len - 1)) * size.width;
        final y = size.height - (bins[i] * (size.height - 8.0));
        fillPath.lineTo(x, y);
        if (i == 0) {
          linePath.moveTo(x, y);
        } else {
          linePath.lineTo(x, y);
        }
      }
      fillPath.lineTo(size.width, size.height);
      fillPath.close();

      canvas.drawPath(
        fillPath,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        linePath,
        Paint()
          ..color = color.withValues(alpha: 0.88)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _paintWaveform(Canvas canvas, Size size) {
    final cellW = size.width / kGridCols;
    final cellH = size.height / kGridRows;
    final bins = data.waveformBins;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int ry = 0; ry < kGridRows; ry++) {
      final top = ry * cellH;
      for (int cx = 0; cx < kGridCols; cx++) {
        final idx = (ry * kGridCols + cx) * 3;
        final r = bins[idx];
        final g = bins[idx + 1];
        final b = bins[idx + 2];
        if ((r | g | b) <= 8) continue;
        paint.color = Color.fromARGB(
          255,
          r.clamp(0, 255),
          g.clamp(0, 255),
          b.clamp(0, 255),
        );
        canvas.drawRect(
          Rect.fromLTWH(cx * cellW, top, cellW + 0.6, cellH + 0.6),
          paint,
        );
      }
    }
  }

  void _paintParade(Canvas canvas, Size size, Paint gridPaint) {
    final cellW = size.width / kGridCols;
    final cellH = size.height / kGridRows;
    final subCols = kGridCols ~/ 3;
    final bins = data.paradeBins;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int ry = 0; ry < kGridRows; ry++) {
      final top = ry * cellH;
      for (int cx = 0; cx < kGridCols; cx++) {
        final v = bins[ry * kGridCols + cx];
        if (v <= 8) continue;
        if (cx < subCols) {
          paint.color = Color.fromARGB(255, v, v ~/ 6, v ~/ 6);
        } else if (cx < subCols * 2) {
          paint.color = Color.fromARGB(255, v ~/ 6, v, v ~/ 6);
        } else {
          paint.color = Color.fromARGB(255, v ~/ 5, (v * 2) ~/ 5, v);
        }
        canvas.drawRect(
          Rect.fromLTWH(cx * cellW, top, cellW + 0.6, cellH + 0.6),
          paint,
        );
      }
    }

    // 3등분 구분선
    canvas.drawLine(
      Offset(size.width / 3.0, 0),
      Offset(size.width / 3.0, size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(size.width * 2.0 / 3.0, 0),
      Offset(size.width * 2.0 / 3.0, size.height),
      gridPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DirectScopePainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.mode != mode;
}

class _EightBandPainter extends CustomPainter {
  final List<double> levels;
  _EightBandPainter({required this.levels});

  static const List<String> _names = [
    'Red',
    'Org',
    'Yel',
    'Grn',
    'Aqu',
    'Blu',
    'Pur',
    'Mag',
  ];

  static const List<Color> _colors = [
    Color(0xFFFF4040),
    Color(0xFFFF8830),
    Color(0xFFFFDD30),
    Color(0xFF45DD45),
    Color(0xFF30DDDD),
    Color(0xFF4588FF),
    Color(0xFF9955FF),
    Color(0xFFFF45CC),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 20 || size.height <= 30) return;
    const padX = 12.0;
    const padTop = 14.0;
    const padBot = 20.0;
    final usableW = (size.width - padX * 2).clamp(1.0, 10000.0);
    final usableH = (size.height - padTop - padBot).clamp(1.0, 10000.0);
    final slotW = usableW / 8.0;
    final barW = slotW * 0.58;

    for (int i = 0; i < 8; i++) {
      final lv = (i < levels.length ? levels[i] : 0.0).clamp(0.0, 1.0);
      final bh = lv * usableH;
      final cx = padX + slotW * (i + 0.5);
      final left = cx - barW * 0.5;
      final top = padTop + usableH - bh;

      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barW, bh),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        barRect,
        Paint()..color = _colors[i].withValues(alpha: 0.85),
      );

      final pctTp = TextPainter(
        text: TextSpan(
          text: '${(lv * 100).round()}%',
          style: const TextStyle(fontSize: 8.5, color: Color(0xFFCCCCCC)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      pctTp.paint(canvas, Offset(cx - pctTp.width * 0.5, top - 11));

      final lblTp = TextPainter(
        text: TextSpan(
          text: _names[i],
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: _colors[i],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      lblTp.paint(
        canvas,
        Offset(cx - lblTp.width * 0.5, size.height - padBot + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EightBandPainter oldDelegate) => true;
}
