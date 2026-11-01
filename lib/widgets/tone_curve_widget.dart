import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../services/curve_lut.dart';
import 'double_tap_tracker.dart';

/// 점 또는 곡선 근처를 터치했을 때만 즉시 GestureArena에서 승리하여
/// 부모 ListView의 수직 스크롤을 막고, 빈 배경 영역을 터치했을 때는
/// 즉시 양보(rejected)하여 모바일에서도 스크롤과 곡선 조작이 완벽히 공존하도록 하는 인식기
class _SelectiveCurvePanGestureRecognizer extends PanGestureRecognizer {
  bool Function(Offset localPosition)? shouldClaimImmediately;

  _SelectiveCurvePanGestureRecognizer({
    this.shouldClaimImmediately,
    super.debugOwner,
  });

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    final claim = shouldClaimImmediately?.call(event.localPosition) ?? false;
    if (claim) {
      resolve(GestureDisposition.accepted);
    } else {
      resolve(GestureDisposition.rejected);
    }
  }
}

/// SemiDarktable의 ToneCurveWidget (모바일 터치 완벽 최적화 버전)
/// - RGB / R / G / B 4채널 지원
/// - Fritsch-Carlson 단조 3차 스플라인 실시간 렌더링
/// - 로컬 상태(_localCurves) 기반 동기화로 제스처 프레임 지연/레이스 컨디션 완벽 차단
/// - 어디를 터치하든 터치한 바로 그 위치(섀도우/미드톤/하이라이트)에 점이 생겨 손가락을 따라 조작되며,
///   오른쪽 위 끝점이 엉뚱하게 잡히는 현상 원천 해결
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

class _ToneCurveWidgetState extends State<ToneCurveWidget>
    with AutomaticKeepAliveClientMixin {
  static const double _pad = 12.0;
  static const double _pointHitRadius = 40.0;
  static const double _endPointHitRadius = 22.0;
  static const double _curveLineHitRadius = 40.0;

  String _activeChannel = 'rgb';
  int? _draggingIndex;
  bool _isDragging = false;
  Offset _grabOffset = Offset.zero;

  final DoubleTapTracker _doubleTap = DoubleTapTracker();
  bool _isDoubleTapGuard = false;

  /// 레이스 컨디션을 막기 위해 위젯 내부에서 일관되게 유지하는 로컬 커브 포인트 맵
  late Map<String, List<List<double>>> _localCurves;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _localCurves = _cloneMap(widget.curvePoints);
  }

  @override
  void didUpdateWidget(covariant ToneCurveWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 사용자가 손가락으로 드래그하고 있는 도중에는 외부 re-build로 인해 상태가 덮어써지지 않도록 보호
    if (!_isDragging) {
      _localCurves = _cloneMap(widget.curvePoints);
    }
  }

  Map<String, List<List<double>>> _cloneMap(Map<String, List<List<double>>> src) {
    final map = <String, List<List<double>>>{};
    for (final ch in ['rgb', 'r', 'g', 'b']) {
      final list = src[ch] ??
          [
            [0.0, 0.0],
            [1.0, 1.0],
          ];
      map[ch] = list.map((p) => [p[0], p[1]]).toList();
    }
    return map;
  }

  List<List<double>> get _currentPoints {
    final pts = _localCurves[_activeChannel];
    if (pts == null || pts.length < 2) {
      final fallback = [
        [0.0, 0.0],
        [1.0, 1.0],
      ];
      _localCurves[_activeChannel] = fallback;
      return fallback;
    }
    return pts;
  }

  Map<String, List<List<double>>> _cloneAll() {
    return _cloneMap(_localCurves);
  }

  /// 터치 위치에서 잡을 제어점 선택.
  /// 1. 중간 제어점을 40px 반경 안에서 우선 탐색
  /// 2. 양 끝점은 X가 극단 가장자리(X <= 5% 또는 X >= 95%)일 때만 선택 허용
  int? _findNearPoint(Offset localPos, Size size, List<List<double>> pts) {
    final w = (size.width - _pad * 2).clamp(1.0, 10000.0);
    final h = (size.height - _pad * 2).clamp(1.0, 10000.0);
    final normX = ((localPos.dx - _pad) / w).clamp(0.0, 1.0);

    // 1순위: 중간 제어점 우선 탐색
    int? bestMid;
    double bestMidDist = _pointHitRadius;
    for (int i = 1; i < pts.length - 1; i++) {
      final px = _pad + pts[i][0] * w;
      final py = _pad + (1.0 - pts[i][1]) * h;
      final d = (Offset(px, py) - localPos).distance;
      if (d < bestMidDist) {
        bestMidDist = d;
        bestMid = i;
      }
    }
    if (bestMid != null) return bestMid;

    // 2순위: 양 끝점은 극단 가장자리(X <= 0.05 또는 X >= 0.95)에서만 선택 허용
    if (normX <= 0.05) {
      final p0x = _pad + pts[0][0] * w;
      final p0y = _pad + (1.0 - pts[0][1]) * h;
      if ((Offset(p0x, p0y) - localPos).distance <= _endPointHitRadius) {
        return 0;
      }
    }
    if (normX >= 0.95) {
      final lastIdx = pts.length - 1;
      final pLastX = _pad + pts[lastIdx][0] * w;
      final pLastY = _pad + (1.0 - pts[lastIdx][1]) * h;
      if ((Offset(pLastX, pLastY) - localPos).distance <= _endPointHitRadius) {
        return lastIdx;
      }
    }

    return null;
  }

  /// 터치 위치에서 현재 활성 채널 스플라인 곡선까지의 최소 거리(px) 계산
  double _distanceToCurve(Offset localPos, Size size, List<List<double>> pts) {
    final w = (size.width - _pad * 2).clamp(1.0, 10000.0);
    final h = (size.height - _pad * 2).clamp(1.0, 10000.0);
    final lut = evaluateMonotoneCubicSpline(pts, 64);
    double minDist = double.infinity;
    for (int i = 0; i < 64; i++) {
      final t = i / 63.0;
      final cx = _pad + t * w;
      final cy = _pad + (1.0 - lut[i].clamp(0.0, 1.0)) * h;
      final d = (Offset(cx, cy) - localPos).distance;
      if (d < minDist) {
        minDist = d;
      }
    }
    return minDist;
  }

  /// 제어점 또는 곡선 근처 터치인지 판별 (빈 배경 스와이프 시에는 부모 스크롤 허용)
  bool _isInteractiveTouch(Offset localPos, Size size) {
    final pts = _currentPoints;
    if (_findNearPoint(localPos, size, pts) != null) {
      return true;
    }
    return _distanceToCurve(localPos, size, pts) <= _curveLineHitRadius;
  }

  Offset _posToNorm(Offset localPos, Size size) {
    final w = (size.width - _pad * 2).clamp(1.0, 10000.0);
    final h = (size.height - _pad * 2).clamp(1.0, 10000.0);
    final nx = ((localPos.dx - _pad) / w).clamp(0.0, 1.0);
    final ny = (1.0 - (localPos.dy - _pad) / h).clamp(0.0, 1.0);
    return Offset(nx, ny);
  }

  void _handlePointerDown(PointerDownEvent event, Size size) {
    if (_doubleTap.onPointerDown(event)) {
      _isDoubleTapGuard = true;
      _isDragging = false;
      _draggingIndex = null;
      _handleDoubleTapAt(event.localPosition, size);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _isDoubleTapGuard = false;
      });
    }
  }

  void _handlePanStart(DragStartDetails details, Size size) {
    if (_isDoubleTapGuard) return;
    final pts = _currentPoints;
    final pos = details.localPosition;
    final norm = _posToNorm(pos, size);

    // 1순위: 확대된 반경 내의 기존 중간 제어점 또는 모퉁이 끝점 확인
    int? hit = _findNearPoint(pos, size, pts);

    // 2순위: 터치 위치의 X좌표가 기존 중간 제어점과 가까운 경우(5% 이내) 그 점을 선택
    if (hit == null) {
      for (int i = 1; i < pts.length - 1; i++) {
        final dx = (pts[i][0] - norm.dx).abs();
        if (dx < 0.05 && (pts[i][1] - norm.dy).abs() < 0.35) {
          hit = i;
          break;
        }
      }
    }

    widget.onChangeStart?.call();
    widget.onAutoTurnOn?.call();

    if (hit != null) {
      // 기존 제어점 잡기
      _grabOffset = Offset(pts[hit][0] - norm.dx, pts[hit][1] - norm.dy);
      _draggingIndex = hit;
      _isDragging = true;
      setState(() {});
    } else if (_distanceToCurve(pos, size, pts) <= _curveLineHitRadius) {
      // 3순위: 곡선 근처를 터치했을 때, 터치한 X좌표(0.05 ~ 0.95 사이)에 새로운 제어점 즉시 생성!
      // 극단 모퉁이(0.05 이하, 0.95 이상)가 아닌 안전한 영역에 새 점이 생성되어 양 끝점이 절대 잡히지 않음
      final newX = norm.dx.clamp(0.05, 0.95);
      final newY = norm.dy.clamp(0.0, 1.0);
      pts.add([newX, newY]);
      pts.sort((a, b) => a[0].compareTo(b[0]));
      int newIdx = 1;
      for (int i = 1; i < pts.length - 1; i++) {
        if ((pts[i][0] - newX).abs() < 1e-4) {
          newIdx = i;
          break;
        }
      }
      _grabOffset = Offset.zero;
      _draggingIndex = newIdx;
      _isDragging = true;
      setState(() {});
      widget.onChanged(_cloneAll());
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    if (_isDoubleTapGuard || !_isDragging) return;
    final idx = _draggingIndex;
    if (idx == null) return;
    final pts = _currentPoints;
    if (idx < 0 || idx >= pts.length) return;

    final norm = _posToNorm(details.localPosition, size);
    double nx = (norm.dx + _grabOffset.dx).clamp(0.0, 1.0);
    final ny = (norm.dy + _grabOffset.dy).clamp(0.0, 1.0);

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
    setState(() {});
    widget.onChanged(_cloneAll());
  }

  void _handlePanEnd(DragEndDetails details) {
    _isDragging = false;
    if (_draggingIndex != null) {
      setState(() => _draggingIndex = null);
    }
    widget.onChangeEnd?.call();
  }

  void _handleDoubleTapAt(Offset localPosition, Size size) {
    widget.onChangeStart?.call();
    widget.onAutoTurnOn?.call();
    final pts = _currentPoints;
    final hit = _findNearPoint(localPosition, size, pts);
    if (hit != null && hit > 0 && hit < pts.length - 1) {
      // 제어점 더블탭 시 해당 제어점 삭제
      pts.removeAt(hit);
    } else {
      // 그래프 빈 곳 더블탭 시 현재 채널 기본 직선으로 초기화
      _localCurves[_activeChannel] = [
        [0.0, 0.0],
        [1.0, 1.0],
      ];
    }
    setState(() {});
    widget.onChanged(_cloneAll());
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
    super.build(context);
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
                  _localCurves[_activeChannel] = [
                    [0.0, 0.0],
                    [1.0, 1.0],
                  ];
                  setState(() {});
                  widget.onChanged(_cloneAll());
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
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFFBBBBBB),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 커브 캔버스 영역 (점/곡선 근처 터치 시 스크롤 차단, 빈 배경 터치 시 스크롤 허용)
        LayoutBuilder(
          builder: (context, constraints) {
            final canvasW =
                constraints.maxWidth.isFinite && constraints.maxWidth > 40
                    ? constraints.maxWidth
                    : 240.0;
            const canvasH = 195.0;
            final size = Size(canvasW, canvasH);

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _handlePointerDown(e, size),
              onPointerMove: _doubleTap.onPointerMove,
              onPointerUp: _doubleTap.onPointerUp,
              onPointerCancel: _doubleTap.onPointerCancel,
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: <Type, GestureRecognizerFactory>{
                  _SelectiveCurvePanGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          _SelectiveCurvePanGestureRecognizer>(
                    () => _SelectiveCurvePanGestureRecognizer(debugOwner: this),
                    (_SelectiveCurvePanGestureRecognizer instance) {
                      instance.shouldClaimImmediately =
                          (pos) => _isInteractiveTouch(pos, size);
                      instance.onStart = (d) => _handlePanStart(d, size);
                      instance.onUpdate = (d) => _handlePanUpdate(d, size);
                      instance.onEnd = _handlePanEnd;
                    },
                  ),
                },
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
                      allPoints: _localCurves,
                      activeChannel: _activeChannel,
                      activeColor: _channelColor(_activeChannel),
                      draggingIndex: _draggingIndex,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        const Text(
          '곡선/포인트 드래그: 추가·이동 (빈 영역 스와이프: 스크롤) | 포인트 더블탭: 삭제',
          style: TextStyle(fontSize: 9.5, color: Color(0xFF777777)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ToneCurvePainter extends CustomPainter {
  static const double _pad = 12.0;

  final Map<String, List<List<double>>> allPoints;
  final String activeChannel;
  final Color activeColor;
  final int? draggingIndex;

  _ToneCurvePainter({
    required this.allPoints,
    required this.activeChannel,
    required this.activeColor,
    this.draggingIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = (size.width - _pad * 2).clamp(1.0, 10000.0);
    final h = (size.height - _pad * 2).clamp(1.0, 10000.0);
    final rect = Rect.fromLTWH(_pad, _pad, w, h);

    // 4x4 격자선
    final gridPaint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final gx = _pad + w * (i / 4.0);
      final gy = _pad + h * (i / 4.0);
      canvas.drawLine(Offset(gx, _pad), Offset(gx, _pad + h), gridPaint);
      canvas.drawLine(Offset(_pad, gy), Offset(_pad + w, gy), gridPaint);
    }

    // 대각선 기준선
    final diagPaint = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(_pad, _pad + h),
      Offset(_pad + w, _pad),
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
    _drawSpline(canvas, rect, activePts, activeColor, 2.4);

    // 활성 채널의 제어점 그리기 (모바일 터치 가시성을 높이기 위해 은은한 외곽 터치 링과 선명한 노드 표시)
    final ptHalo = Paint()
      ..color = activeColor.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;
    final ptActiveHalo = Paint()
      ..color = activeColor.withValues(alpha: 0.38)
      ..style = PaintingStyle.fill;
    final ptFill = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    final ptBorder = Paint()
      ..color = const Color(0xFF121212)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < activePts.length; i++) {
      final p = activePts[i];
      final px = _pad + p[0].clamp(0.0, 1.0) * w;
      final py = _pad + (1.0 - p[1].clamp(0.0, 1.0)) * h;
      final center = Offset(px, py);
      final isDragging = draggingIndex == i;
      canvas.drawCircle(
        center,
        isDragging ? 14.0 : 10.0,
        isDragging ? ptActiveHalo : ptHalo,
      );
      canvas.drawCircle(center, isDragging ? 6.5 : 5.5, ptFill);
      canvas.drawCircle(center, isDragging ? 6.5 : 5.5, ptBorder);
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
