import 'dart:math' as math;
import 'package:flutter/material.dart';

/// SemiDarktable의 ColorEqualizerWidget 1:1 이식
/// - 3개 모드 탭: 🎨 Hue (색상), ✨ Saturation (채도), 💡 Brightness (밝기)
/// - 무지개 HSL 스펙트럼 배경 캔버스 위에 8개 색상 밴드(Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta) 노드를 배치
/// - 노드를 상하로 드래그하여 -100 ~ +100 직관적 조절, 노드 더블클릭 시 해당 밴드 0으로 초기화
class ColorEqualizerWidget extends StatefulWidget {
  final List<double> hue;
  final List<double> sat;
  final List<double> bri;
  final void Function(List<double> hue, List<double> sat, List<double> bri)
      onChanged;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;
  final VoidCallback? onAutoTurnOn;

  const ColorEqualizerWidget({
    super.key,
    required this.hue,
    required this.sat,
    required this.bri,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onAutoTurnOn,
  });

  @override
  State<ColorEqualizerWidget> createState() => _ColorEqualizerWidgetState();
}

class _ColorEqualizerWidgetState extends State<ColorEqualizerWidget> {
  // 'hue', 'sat', 'bri'
  String _mode = 'sat';
  int? _activeNode;

  static const List<String> _bandLabels = [
    'R',
    'O',
    'Y',
    'G',
    'A',
    'B',
    'P',
    'M',
  ];

  static const List<Color> _bandColors = [
    Color(0xFFFF4040),
    Color(0xFFFF8830),
    Color(0xFFFFDD30),
    Color(0xFF45DD45),
    Color(0xFF30DDDD),
    Color(0xFF4588FF),
    Color(0xFF9955FF),
    Color(0xFFFF45CC),
  ];

  List<double> get _currentValues {
    switch (_mode) {
      case 'hue':
        return List<double>.from(widget.hue);
      case 'bri':
        return List<double>.from(widget.bri);
      case 'sat':
      default:
        return List<double>.from(widget.sat);
    }
  }

  void _emitUpdated(List<double> vals) {
    final h = List<double>.from(widget.hue);
    final s = List<double>.from(widget.sat);
    final b = List<double>.from(widget.bri);
    if (_mode == 'hue') {
      widget.onChanged(vals, s, b);
    } else if (_mode == 'bri') {
      widget.onChanged(h, s, vals);
    } else {
      widget.onChanged(h, vals, b);
    }
  }

  int _nodeFromPosition(Offset localPos, Size size) {
    const padX = 16.0;
    final usableW = (size.width - padX * 2).clamp(1.0, 10000.0);
    final step = usableW / 7.0;
    final idx = ((localPos.dx - padX) / step).round().clamp(0, 7);
    return idx;
  }

  double _valFromPosition(Offset localPos, Size size) {
    const padY = 14.0;
    final usableH = (size.height - padY * 2).clamp(1.0, 10000.0);
    final norm = ((localPos.dy - padY) / usableH).clamp(0.0, 1.0);
    return ((0.5 - norm) * 2.0).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final vals = _currentValues;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 상단 3개 탭 (🎨 Hue / ✨ Saturation / 💡 Brightness)
        Row(
          children: [
            for (final tab in [
              ('hue', '🎨 색상(Hue)'),
              ('sat', '✨ 채도(Sat)'),
              ('bri', '💡 밝기(Bri)'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () => setState(() => _mode = tab.$1),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _mode == tab.$1
                            ? const Color(0xFF3E3524)
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _mode == tab.$1
                              ? const Color(0xFFE8A838)
                              : const Color(0xFF333333),
                        ),
                      ),
                      child: Text(
                        tab.$2,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: _mode == tab.$1
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _mode == tab.$1
                              ? const Color(0xFFE8A838)
                              : const Color(0xFFAAAAAA),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // 인터랙티브 스펙트럼 이퀄라이저 캔버스
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite && constraints.maxWidth > 40
                ? constraints.maxWidth
                : 240.0;
            const h = 155.0;
            final size = Size(w, h);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) {
                widget.onChangeStart?.call();
                widget.onAutoTurnOn?.call();
                final idx = _nodeFromPosition(d.localPosition, size);
                setState(() => _activeNode = idx);
                final updated = _currentValues;
                updated[idx] = _valFromPosition(d.localPosition, size);
                _emitUpdated(updated);
              },
              onPanUpdate: (d) {
                final idx =
                    _activeNode ?? _nodeFromPosition(d.localPosition, size);
                final updated = _currentValues;
                updated[idx] = _valFromPosition(d.localPosition, size);
                _emitUpdated(updated);
              },
              onPanEnd: (_) {
                setState(() => _activeNode = null);
                widget.onChangeEnd?.call();
              },
              onDoubleTapDown: (d) {
                widget.onChangeStart?.call();
                widget.onAutoTurnOn?.call();
                final idx = _nodeFromPosition(d.localPosition, size);
                final updated = _currentValues;
                updated[idx] = 0.0;
                _emitUpdated(updated);
                widget.onChangeEnd?.call();
              },
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFF3A3A3A)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CustomPaint(
                    size: size,
                    painter: _ColorEqPainter(
                      values: vals,
                      activeNode: _activeNode,
                      bandColors: _bandColors,
                      bandLabels: _bandLabels,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        // 하단 수치 요약 및 현재 탭 초기화 버튼
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(
              child: Text(
                '노드 상하 드래그: 조절 | 더블클릭: 0 초기화',
                style: TextStyle(fontSize: 9.5, color: Color(0xFF777777)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              onTap: () {
                widget.onChangeStart?.call();
                _emitUpdated(List<double>.filled(8, 0.0));
                widget.onChangeEnd?.call();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  '현재 탭 초기화',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFFE8A838),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorEqPainter extends CustomPainter {
  final List<double> values;
  final int? activeNode;
  final List<Color> bandColors;
  final List<String> bandLabels;

  _ColorEqPainter({
    required this.values,
    required this.activeNode,
    required this.bandColors,
    required this.bandLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 어두운 레인보우 그라데이션 배경
    final bgGradient = LinearGradient(
      colors: bandColors
          .map((c) => Color.lerp(const Color(0xFF161616), c, 0.22)!)
          .toList(),
    );
    canvas.drawRect(rect, Paint()..shader = bgGradient.createShader(rect));

    const padX = 16.0;
    const padY = 14.0;
    final usableW = (size.width - padX * 2).clamp(1.0, 10000.0);
    final usableH = (size.height - padY * 2).clamp(1.0, 10000.0);
    final midY = padY + usableH * 0.5;

    // 중앙 0 기준선 및 상/하 보조선
    final zeroPaint = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(padX, midY), Offset(padX + usableW, midY), zeroPaint);

    final subGridPaint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(padX, padY + usableH * 0.25),
      Offset(padX + usableW, padY + usableH * 0.25),
      subGridPaint,
    );
    canvas.drawLine(
      Offset(padX, padY + usableH * 0.75),
      Offset(padX + usableW, padY + usableH * 0.75),
      subGridPaint,
    );

    // 8개 노드의 좌표 계산 (내부 값 범위: -1.0 ~ +1.0, 화면 표시: -100 ~ +100)
    final nodeOffsets = <Offset>[];
    for (int i = 0; i < 8; i++) {
      final x = padX + (i / 7.0) * usableW;
      final v = (i < values.length ? values[i] : 0.0).clamp(-1.0, 1.0);
      final y = midY - v * (usableH * 0.5);
      nodeOffsets.add(Offset(x, y));

      // 수직 가이드선
      canvas.drawLine(
        Offset(x, padY),
        Offset(x, padY + usableH),
        subGridPaint,
      );
    }

    // 부드러운 코사인 보간 곡선 연결
    final curvePath = Path();
    for (int i = 0; i < 7; i++) {
      final p0 = nodeOffsets[i];
      final p1 = nodeOffsets[i + 1];
      if (i == 0) curvePath.moveTo(p0.dx, p0.dy);
      const segs = 16;
      for (int s = 1; s <= segs; s++) {
        final t = s / segs;
        final ct = (1.0 - math.cos(t * math.pi)) * 0.5;
        final x = p0.dx + (p1.dx - p0.dx) * t;
        final y = p0.dy + (p1.dy - p0.dy) * ct;
        curvePath.lineTo(x, y);
      }
    }

    canvas.drawPath(
      curvePath,
      Paint()
        ..color = const Color(0xDDE8A838)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // 각 노드 원 및 라벨/수치 표시
    for (int i = 0; i < 8; i++) {
      final pt = nodeOffsets[i];
      final isCurrent = activeNode == i;
      final radius = isCurrent ? 6.5 : 5.0;

      canvas.drawCircle(
        pt,
        radius,
        Paint()
          ..color = bandColors[i]
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        pt,
        radius,
        Paint()
          ..color = isCurrent ? Colors.white : const Color(0xFF141414)
          ..strokeWidth = isCurrent ? 2.0 : 1.5
          ..style = PaintingStyle.stroke,
      );

      // 하단 밴드 이름 표시
      final tp = TextPainter(
        text: TextSpan(
          text: bandLabels[i],
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            color: bandColors[i],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pt.dx - tp.width / 2, size.height - 12));

      // 값이 변경되었거나 드래그 중인 경우 수치 툴팁 표시
      final vPct = (i < values.length ? values[i] : 0.0) * 100.0;
      if (vPct.abs() > 0.5 || isCurrent) {
        final vTp = TextPainter(
          text: TextSpan(
            text: vPct > 0 ? '+${vPct.round()}' : '${vPct.round()}',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelY = pt.dy > 24 ? pt.dy - 14 : pt.dy + 7;
        vTp.paint(canvas, Offset(pt.dx - vTp.width / 2, labelY));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ColorEqPainter oldDelegate) => true;
}
