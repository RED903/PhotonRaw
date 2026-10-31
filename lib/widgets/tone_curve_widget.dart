import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/curve_lut.dart';

/// SemiDarktable의 ToneCurveWidget 1:1 이식
/// - RGB / R / G / B 4채널 탭 지원
/// - Fritsch-Carlson 단조 3차 스플라인 실시간 곡선 렌더링
/// - 명시적인 SizedBox(width: double.infinity, height: 190)을 사용하여
///   어떤 창 크기에서도 곡선이 사라지거나 레이아웃 오류가 나지 않도록 보장
/// - 점 클릭/드래그 이동, 점 더블클릭 시 삭제, 빈 공간 더블클릭 시 채널 초기화
class ToneCurveWidget extends StatefulWidget {
  final Map<String, List<List<double>>> curvePoints;
  final ValueChanged<Map<String, List<List<double>>>> onChanged;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;
  final VoidCallback? onAutoTurnOn;

  const ToneCurveWidget({
    super.key,
    required this.curvePoints,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onAutoTurnOn,
  });

  @override
  State<ToneCurveWidget> createState() => _ToneCurveWidgetState();
}

class _ToneCurveWidgetState extends State<ToneCurveWidget> {
  String _activeChannel = 'rgb';
  int? _draggingIndex;

  List<List<double>> get _currentPoints {
    final pts = widget.curvePoints[_activeChannel];
    if (pts == null || pts.length < 2) {
      return [
        [0.0, 0.0],
        [1.0, 1.0],
      ];
    }
    return pts.map((p) => [p[0], p[1]]).toList();
  }

  Map<String, List<List<double>>> _cloneAll() {
    final map = <String, List<List<double>>>{};
    for (final ch in ['rgb', 'r', 'g', 'b']) {
      final src = widget.curvePoints[ch] ??
          [
            [0.0, 0.0],
            [1.0, 1.0],
          ];
      map[ch] = src.map((p) => [p[0], p[1]]).toList();
    }
    return map;
  }

  int? _findNearPoint(Offset localPos, Size size, List<List<double>> pts) {
    const pad = 10.0;
    final w = (size.width - pad * 2).clamp(1.0, 10000.0);
    final h = (size.height - pad * 2).clamp(1.0, 10000.0);

    int? bestIdx;
    double bestDist = 14.0;
    for (int i = 0; i < pts.length; i++) {
      final px = pad + pts[i][0] * w;
      final py = pad + (1.0 - pts[i][1]) * h;
      final d = (Offset(px, py) - localPos).distance;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  Offset _posToNorm(Offset localPos, Size size) {
    const pad = 10.0;
    final w = (size.width - pad * 2).clamp(1.0, 10000.0);
    final h = (size.height - pad * 2).clamp(1.0, 10000.0);
    final nx = ((localPos.dx - pad) / w).clamp(0.0, 1.0);
    final ny = (1.0 - (localPos.dy - pad) / h).clamp(0.0, 1.0);
    return Offset(nx, ny);
  }

  void _handlePanStart(DragStartDetails details, Size size) {
    widget.onChangeStart?.call();
    widget.onAutoTurnOn?.call();
    final pts = _currentPoints;
    final hit = _findNearPoint(details.localPosition, size, pts);
    if (hit != null) {
      _draggingIndex = hit;
    } else {
      final norm = _posToNorm(details.localPosition, size);
      pts.add([norm.dx, norm.dy]);
      pts.sort((a, b) => a[0].compareTo(b[0]));
      int newIdx = 0;
      double minDiff = 999.0;
      for (int i = 0; i < pts.length; i++) {
        final d = (pts[i][0] - norm.dx).abs() + (pts[i][1] - norm.dy).abs();
        if (d < minDiff) {
          minDiff = d;
          newIdx = i;
        }
      }
      _draggingIndex = newIdx;
      final updated = _cloneAll();
      updated[_activeChannel] = pts;
      widget.onChanged(updated);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    final idx = _draggingIndex;
    if (idx == null) return;
    final pts = _currentPoints;
    if (idx < 0 || idx >= pts.length) return;

    final norm = _posToNorm(details.localPosition, size);
    double nx = norm.dx;
    final ny = norm.dy;

    if (idx == 0) {
      nx = 0.0;
    } else if (idx == pts.length - 1) {
      nx = 1.0;
    } else {
      final leftX = pts[idx - 1][0] + 0.01;
      final rightX = pts[idx + 1][0] - 0.01;
      nx = nx.clamp(leftX, rightX);
    }

    pts[idx] = [nx, ny];
    final updated = _cloneAll();
    updated[_activeChannel] = pts;
    widget.onChanged(updated);
  }

  void _handlePanEnd(DragEndDetails details) {
    _draggingIndex = null;
    widget.onChangeEnd?.call();
  }

  void _handleDoubleTapDown(TapDownDetails details, Size size) {
    widget.onChangeStart?.call();
    widget.onAutoTurnOn?.call();
    final pts = _currentPoints;
    final hit = _findNearPoint(details.localPosition, size, pts);
    final updated = _cloneAll();
    if (hit != null && hit > 0 && hit < pts.length - 1) {
      pts.removeAt(hit);
      updated[_activeChannel] = pts;
    } else {
      updated[_activeChannel] = [
        [0.0, 0.0],
        [1.0, 1.0],
      ];
    }
    widget.onChanged(updated);
    widget.onChangeEnd?.call();
  }

  Color _channelColor(String ch) {
    switch (ch) {
      case 'r':
        return const Color(0xFFFF5555);
      case 'g':
        return const Color(0xFF55DD55);
      case 'b':
        return const Color(0xFF5599FF);
      default:
        return const Color(0xFFE0E0E0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 채널 선택 버튼 행 (RGB / R / G / B + 채널 초기화)
        Row(
          children: [
            for (final entry in [
              ('rgb', 'RGB', const Color(0xFFE0E0E0)),
              ('r', 'R', const Color(0xFFFF5555)),
              ('g', 'G', const Color(0xFF55DD55)),
              ('b', 'B', const Color(0xFF5599FF)),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => setState(() => _activeChannel = entry.$1),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _activeChannel == entry.$1
                            ? const Color(0xFF3A3A3A)
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _activeChannel == entry.$1
                              ? entry.$3
                              : const Color(0xFF333333),
                        ),
                      ),
                      child: Text(
                        entry.$2,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: entry.$3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Tooltip(
              message: '현재 선택된 채널 커브 초기화',
              child: InkWell(
                onTap: () {
                  widget.onChangeStart?.call();
                  final updated = _cloneAll();
                  updated[_activeChannel] = [
                    [0.0, 0.0],
                    [1.0, 1.0],
                  ];
                  widget.onChanged(updated);
                  widget.onChangeEnd?.call();
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF3A3A3A)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '초기화',
                        style: TextStyle(fontSize: 10.5, color: Color(0xFFBBBBBB)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 커브 캔버스 영역 (명시적인 폭/높이 지정으로 항상 정상 표시 보장)
        LayoutBuilder(
          builder: (context, constraints) {
            final canvasW = constraints.maxWidth.isFinite &&
                    constraints.maxWidth > 40
                ? constraints.maxWidth
                : 240.0;
            const canvasH = 185.0;
            final size = Size(canvasW, canvasH);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _handlePanStart(d, size),
              onPanUpdate: (d) => _handlePanUpdate(d, size),
              onPanEnd: _handlePanEnd,
              onDoubleTapDown: (d) => _handleDoubleTapDown(d, size),
              child: Container(
                width: canvasW,
                height: canvasH,
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF383838)),
                ),
                child: CustomPaint(
                  size: size,
                  painter: _ToneCurvePainter(
                    allPoints: widget.curvePoints,
                    activeChannel: _activeChannel,
                    activeColor: _channelColor(_activeChannel),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        const Text(
          '클릭/드래그: 포인트 추가·이동 | 포인트 더블클릭: 삭제 | 빈 공간 더블클릭: 초기화',
          style: TextStyle(fontSize: 9.5, color: Color(0xFF777777)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ToneCurvePainter extends CustomPainter {
  final Map<String, List<List<double>>> allPoints;
  final String activeChannel;
  final Color activeColor;

  _ToneCurvePainter({
    required this.allPoints,
    required this.activeChannel,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 10.0;
    final w = (size.width - pad * 2).clamp(1.0, 10000.0);
    final h = (size.height - pad * 2).clamp(1.0, 10000.0);
    final rect = Rect.fromLTWH(pad, pad, w, h);

    // 4x4 격자선
    final gridPaint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final gx = pad + w * (i / 4.0);
      final gy = pad + h * (i / 4.0);
      canvas.drawLine(Offset(gx, pad), Offset(gx, pad + h), gridPaint);
      canvas.drawLine(Offset(pad, gy), Offset(pad + w, gy), gridPaint);
    }

    // 대각선 기준선
    final diagPaint = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(pad, pad + h),
      Offset(pad + w, pad),
      diagPaint,
    );

    // 비활성 채널들을 반투명하게 먼저 그림
    final bgChannels = <String, Color>{
      'rgb': const Color(0x55CCCCCC),
      'r': const Color(0x55FF5555),
      'g': const Color(0x5555DD55),
      'b': const Color(0x555599FF),
    };
    for (final entry in bgChannels.entries) {
      if (entry.key == activeChannel) continue;
      final pts = allPoints[entry.key];
      if (pts == null || isIdentityCurve(pts)) continue;
      _drawSpline(canvas, rect, pts, entry.value, 1.3);
    }

    // 활성 채널 스플라인 곡선 그리기
    final activePts = allPoints[activeChannel] ??
        [
          [0.0, 0.0],
          [1.0, 1.0],
        ];
    _drawSpline(canvas, rect, activePts, activeColor, 2.2);

    // 활성 채널의 제어점 그리기
    final ptFill = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    final ptBorder = Paint()
      ..color = const Color(0xFF121212)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final p in activePts) {
      final px = pad + p[0].clamp(0.0, 1.0) * w;
      final py = pad + (1.0 - p[1].clamp(0.0, 1.0)) * h;
      canvas.drawCircle(Offset(px, py), 4.5, ptFill);
      canvas.drawCircle(Offset(px, py), 4.5, ptBorder);
    }
  }

  void _drawSpline(
    Canvas canvas,
    Rect rect,
    List<List<double>> pts,
    Color color,
    double width,
  ) {
    final Float32List lut = evaluateMonotoneCubicSpline(pts, 128);
    final path = Path();
    for (int i = 0; i < 128; i++) {
      final t = i / 127.0;
      final x = rect.left + t * rect.width;
      final y = rect.top + (1.0 - lut[i].clamp(0.0, 1.0)) * rect.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ToneCurvePainter oldDelegate) => true;
}
