import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'double_tap_tracker.dart';

/// 8개 밴드 노드(32px) 또는 이퀄라이저 스플라인 곡선(26px) 근처를 터치했을 때만
/// 즉시 GestureArena에서 승리하여 부모 ListView의 수직 스크롤을 차단하고,
/// 곡선/노드에서 먼 빈 배경을 밀 때는 스크롤이 작동하도록 하는 인식기
class _SelectiveEqPanGestureRecognizer extends PanGestureRecognizer {
  bool Function(Offset localPosition)? shouldClaimImmediately;

  _SelectiveEqPanGestureRecognizer({
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

/// SemiDarktable의 ColorEqualizerWidget (widgets.py 601~819행) 1:1 완벽 이식 + 모바일 터치/스크롤 공존 최적화
/// - 기본 시작 탭: 🎨 Hue (색조) — 스크롤 이동 시에도 선택된 모드 탭 유지
/// - 모드별 고유 2D HSL 스펙트럼 배경 맵:
///   1) Hue (색조): 상하 위치에 따라 Hue가 ±55° 회전하는 대각선 무지개 스펙트럼
///   2) Saturation (채도): 상단 고채도(100%) 무지개에서 하단 무채색 회색(2%)으로 이어지는 스펙트럼
///   3) Brightness (밝기): 상단 밝은 파스텔(L=94%)에서 하단 어두운 딥톤(L=9%)으로 이어지는 스펙트럼
/// - 8개 대역 수직 점선, 중앙 흰색 기준선, 양 끝이 원형 순환 연결되는 흰색 Smoothstep 스플라인 곡선(그림자 포함), 흰 테두리 원형 노드
/// - 모바일에서 상하 드래그 시 ListView 스크롤에 뺏기지 않도록 노드(32px)·곡선(26px) 터치 시 제스처 즉시 선점
class ColorEqualizerWidget extends StatefulWidget {
  final List<double> hue;
  final List<double> sat;
  final List<double> bri;
  final String? mode;
  final ValueChanged<String>? onModeChanged;
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
    this.mode,
    this.onModeChanged,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onAutoTurnOn,
  });

  @override
  State<ColorEqualizerWidget> createState() => _ColorEqualizerWidgetState();
}

class _ColorEqualizerWidgetState extends State<ColorEqualizerWidget>
    with AutomaticKeepAliveClientMixin {
  static const double _nodeHitRadius = 32.0;
  static const double _curveHitRadius = 26.0;

  // SemiDarktable 기본 시작 모드: 'hue' ('hue', 'sat', 'bri')
  late String _internalMode;
  int? _selectedBand;
  final DoubleTapTracker _doubleTap = DoubleTapTracker();

  @override
  bool get wantKeepAlive => true;

  String get _activeMode => widget.mode ?? _internalMode;

  // SemiDarktable widgets.py 624~628행과 100% 동일한 8밴드 중심 좌표 및 노드 색상
  static const List<double> _centers = [
    0.0625,
    0.1875,
    0.3125,
    0.4375,
    0.5625,
    0.6875,
    0.8125,
    0.9375,
  ];

  static const List<Color> _bandColors = [
    Color(0xFFFF3B30), // Red
    Color(0xFFFF9500), // Orange
    Color(0xFFFFCC00), // Yellow
    Color(0xFF34C759), // Green
    Color(0xFF00C7BE), // Aqua
    Color(0xFF007AFF), // Blue
    Color(0xFF5856D6), // Indigo/Purple
    Color(0xFFAF52DE), // Violet/Magenta
  ];

  @override
  void initState() {
    super.initState();
    _internalMode = widget.mode ?? 'hue';
  }

  @override
  void didUpdateWidget(covariant ColorEqualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != null && widget.mode != _internalMode) {
      _internalMode = widget.mode!;
    }
  }

  void _setMode(String m) {
    setState(() {
      _internalMode = m;
      _selectedBand = null;
    });
    widget.onModeChanged?.call(m);
  }

  List<double> get _currentValues {
    switch (_activeMode) {
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
    if (_activeMode == 'hue') {
      widget.onChanged(vals, s, b);
    } else if (_activeMode == 'bri') {
      widget.onChanged(h, s, vals);
    } else {
      widget.onChanged(h, vals, b);
    }
  }

  /// 주어진 x좌표에서의 스플라인 곡선 Y좌표 계산
  double _evalSplineYAt(double dx, double width, double height, List<double> vals) {
    final midY = height / 2.0;
    final normX = (dx / width).clamp(0.0, 1.0);
    double val = 0.0;
    for (int i = 0; i < 8; i++) {
      double dist = (normX - _centers[i]).abs();
      if (dist > 0.5) {
        dist = 1.0 - dist;
      }
      double weight = (1.0 - (dist / 0.16)).clamp(0.0, 1.0);
      weight = weight * weight * (3.0 - 2.0 * weight);
      final v = i < vals.length ? vals[i] : 0.0;
      val += v * weight;
    }
    val = val.clamp(-1.0, 1.0);
    return midY - (val * (midY - 14.0));
  }

  /// 터치 위치가 8개 밴드 노드(32px 반경) 또는 스플라인 곡선(26px 반경) 안쪽인지 판별
  bool _isInteractiveTouch(Offset localPos, double width, double height) {
    final vals = _currentValues;
    final midY = height / 2.0;

    for (int i = 0; i < 8; i++) {
      final px = _centers[i] * width;
      final v = (i < vals.length ? vals[i] : 0.0).clamp(-1.0, 1.0);
      final py = midY - (v * (midY - 14.0));
      if ((Offset(px, py) - localPos).distance <= _nodeHitRadius) {
        return true;
      }
    }

    final curveY = _evalSplineYAt(localPos.dx, width, height, vals);
    return (localPos.dy - curveY).abs() <= _curveHitRadius;
  }

  int _hitTestBand(Offset localPos, double width, double height) {
    final vals = _currentValues;
    final midY = height / 2.0;

    // 1순위: 32px 반경 내에서 실제 노드(px, py)와의 2D 유클리드 거리가 가장 가까운 밴드
    int? bestNodeIdx;
    double bestNodeDist = _nodeHitRadius;
    for (int i = 0; i < 8; i++) {
      final px = _centers[i] * width;
      final v = (i < vals.length ? vals[i] : 0.0).clamp(-1.0, 1.0);
      final py = midY - (v * (midY - 14.0));
      final d = (Offset(px, py) - localPos).distance;
      if (d < bestNodeDist) {
        bestNodeDist = d;
        bestNodeIdx = i;
      }
    }
    if (bestNodeIdx != null) {
      return bestNodeIdx;
    }

    // 2순위: 수평 X좌표 기준 가장 가까운 밴드 반환
    int closest = 0;
    double minDist = double.infinity;
    for (int i = 0; i < 8; i++) {
      final d = (localPos.dx - _centers[i] * width).abs();
      if (d < minDist) {
        minDist = d;
        closest = i;
      }
    }
    return closest;
  }

  double _valFromMouseY(double my, double height) {
    final midY = height / 2.0;
    final denom = (midY - 14.0).clamp(1.0, 10000.0);
    return ((midY - my) / denom).clamp(-1.0, 1.0);
  }

  void _handlePointerDownForDoubleTap(
    PointerDownEvent event,
    double width,
    double height,
  ) {
    if (_doubleTap.onPointerDown(event)) {
      _handleDoubleTapAt(event.localPosition, width, height);
    }
  }

  void _handleDoubleTapAt(Offset localPos, double width, double height) {
    widget.onChangeStart?.call();
    widget.onAutoTurnOn?.call();
    final vals = _currentValues;
    final midY = height / 2.0;

    int hitBand = -1;
    double bestDist = _nodeHitRadius;
    for (int i = 0; i < 8; i++) {
      final px = _centers[i] * width;
      final v = (i < vals.length ? vals[i] : 0.0).clamp(-1.0, 1.0);
      final py = midY - (v * (midY - 14.0));
      final d = (Offset(px, py) - localPos).distance;
      if (d < bestDist) {
        bestDist = d;
        hitBand = i;
      }
    }

    if (hitBand != -1) {
      final updated = _currentValues;
      updated[hitBand] = 0.0;
      _emitUpdated(updated);
    } else {
      _emitUpdated(List<double>.filled(8, 0.0));
    }
    setState(() => _selectedBand = null);
    widget.onChangeEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mode = _activeMode;
    final vals = _currentValues;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // SemiDarktable main.py 1118행과 동일한 3개 모드 버튼
        Row(
          children: [
            for (final tab in [
              ('hue', '🎨 Hue (색조)'),
              ('sat', '✨ Saturation (채도)'),
              ('bri', '💡 Brightness (밝기)'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () => _setMode(tab.$1),
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: mode == tab.$1
                            ? const Color(0xFF332512)
                            : const Color(0xFF202020),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: mode == tab.$1
                              ? const Color(0xFFDCA353)
                              : const Color(0xFF333333),
                        ),
                      ),
                      child: Text(
                        tab.$2,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: mode == tab.$1
                              ? Colors.white
                              : const Color(0xFF888888),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // SemiDarktable widgets.py ColorEqualizerWidget 캔버스 (148px 높이)
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite && constraints.maxWidth > 40
                ? constraints.maxWidth
                : 240.0;
            const h = 148.0;
            final size = Size(w, h);

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _handlePointerDownForDoubleTap(e, w, h),
              onPointerMove: _doubleTap.onPointerMove,
              onPointerUp: _doubleTap.onPointerUp,
              onPointerCancel: _doubleTap.onPointerCancel,
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: <Type, GestureRecognizerFactory>{
                  _SelectiveEqPanGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          _SelectiveEqPanGestureRecognizer>(
                    () => _SelectiveEqPanGestureRecognizer(debugOwner: this),
                    (_SelectiveEqPanGestureRecognizer instance) {
                      instance.shouldClaimImmediately =
                          (pos) => _isInteractiveTouch(pos, w, h);
                      instance.onStart = (d) {
                        widget.onChangeStart?.call();
                        widget.onAutoTurnOn?.call();
                        final band = _hitTestBand(d.localPosition, w, h);
                        setState(() => _selectedBand = band);
                        final updated = _currentValues;
                        updated[band] = _valFromMouseY(d.localPosition.dy, h);
                        _emitUpdated(updated);
                      };
                      instance.onUpdate = (d) {
                        final band = _selectedBand;
                        if (band != null) {
                          final updated = _currentValues;
                          updated[band] =
                              _valFromMouseY(d.localPosition.dy, h);
                          _emitUpdated(updated);
                        }
                      };
                      instance.onEnd = (_) {
                        setState(() => _selectedBand = null);
                        widget.onChangeEnd?.call();
                      };
                    },
                  ),
                },
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF2D2D2D)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 2D HSL 스펙트럼 배경은 모드('hue', 'sat', 'bri')가 바뀔 때만 그리도록 RepaintBoundary로 완전 캐싱
                        RepaintBoundary(
                          child: CustomPaint(
                            size: size,
                            painter: _ColorEqBgPainter(
                              mode: mode,
                              centers: _centers,
                            ),
                          ),
                        ),
                        // 드래그 중에는 가벼운 스플라인 곡선과 8개 노드만 즉시 리페인트 (120fps)
                        CustomPaint(
                          size: size,
                          painter: _ColorEqOverlayPainter(
                            values: vals,
                            centers: _centers,
                            bandColors: _bandColors,
                            selectedBand: _selectedBand,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        const Text(
          '노드/곡선 드래그: 대역 조절 (빈 영역 스와이프: 스크롤) | 노드 더블탭: 초기화',
          style: TextStyle(fontSize: 9.5, color: Color(0xFF777777)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ColorEqBgPainter extends CustomPainter {
  final String mode;
  final List<double> centers;

  _ColorEqBgPainter({
    required this.mode,
    required this.centers,
  });

  /// SemiDarktable widgets.py 679~692행 get_base_hue 1:1 이식
  static double _getBaseHue(double normX) {
    const c = [0.0625, 0.1875, 0.3125, 0.4375, 0.5625, 0.6875, 0.8125, 0.9375];
    const h = [0.0, 35.0, 60.0, 120.0, 180.0, 240.0, 280.0, 325.0];

    if (normX <= c[0]) {
      final t = normX / c[0];
      return (340.0 + t * 20.0) % 360.0;
    }
    if (normX >= c[7]) {
      final t = (normX - c[7]) / (1.0 - c[7]);
      return (325.0 + t * 20.0) % 360.0;
    }
    for (int i = 0; i < 7; i++) {
      if (c[i] <= normX && normX <= c[i + 1]) {
        final t = (normX - c[i]) / (c[i + 1] - c[i]);
        return h[i] + t * (h[i + 1] - h[i]);
      }
    }
    return (normX * 360.0) % 360.0;
  }

  /// SemiDarktable widgets.py 705~717행의 (normX, normY) HSL 픽셀 색상과 100% 동일한 계산
  static Color _evalHslBgColor(String mode, double normX, double normY) {
    final baseHue = _getBaseHue(normX);
    if (mode == 'hue') {
      final hueShift = (0.5 - normY) * 110.0;
      final curHue = ((baseHue + hueShift) % 360.0 + 360.0) % 360.0;
      final light = (0.54 + (0.5 - normY) * 0.12).clamp(0.0, 1.0);
      return HSLColor.fromAHSL(1.0, curHue, 0.85, light).toColor();
    } else if (mode == 'sat') {
      final sat = (1.0 - normY * 0.95).clamp(0.02, 1.0);
      return HSLColor.fromAHSL(1.0, baseHue, sat, 0.52).toColor();
    } else {
      final light = (0.94 - normY * 0.85).clamp(0.05, 0.95);
      return HSLColor.fromAHSL(1.0, baseHue, 0.70, light).toColor();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // 1. 2D HSL 스펙트럼 배경 렌더링 (모드 변경 시에만 1회 실행 후 GPU 텍스처로 캐싱됨)
    const int rows = 40;
    const int cols = 32;
    final stopPositions = List<double>.generate(
      cols + 1,
      (i) => i / cols.toDouble(),
    );
    final rowH = h / rows;

    for (int r = 0; r < rows; r++) {
      final normY = (r + 0.5) / rows;
      final rowColors = List<Color>.generate(
        cols + 1,
        (c) => _evalHslBgColor(mode, c / cols.toDouble(), normY),
      );
      final stripRect = Rect.fromLTWH(0, r * rowH, w, rowH + 0.8);
      final paint = Paint()
        ..shader = LinearGradient(
          colors: rowColors,
          stops: stopPositions,
        ).createShader(stripRect);
      canvas.drawRect(stripRect, paint);
    }

    // 2. 8개 대역 구분 수직 점선 격자
    final gridPaint = Paint()
      ..color = const Color.fromARGB(90, 0, 0, 0)
      ..strokeWidth = 1.0;
    for (final c in centers) {
      final cx = c * w;
      double y = 0;
      while (y < h) {
        final yEnd = (y + 4.0).clamp(0.0, h);
        canvas.drawLine(Offset(cx, y), Offset(cx, yEnd), gridPaint);
        y += 7.0;
      }
    }

    // 3. 중심 기준선 0.0 Neutral
    final midY = h / 2.0;
    canvas.drawLine(
      Offset(0, midY),
      Offset(w, midY),
      Paint()
        ..color = const Color.fromARGB(160, 255, 255, 255)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorEqBgPainter oldDelegate) {
    return oldDelegate.mode != mode;
  }
}

class _ColorEqOverlayPainter extends CustomPainter {
  final List<double> values;
  final List<double> centers;
  final List<Color> bandColors;
  final int? selectedBand;

  _ColorEqOverlayPainter({
    required this.values,
    required this.centers,
    required this.bandColors,
    this.selectedBand,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final midY = h / 2.0;

    // 4. 양 끝이 자연스럽게 이어지는 원형 순환 Smoothstep 스플라인 곡선
    final path = Path();
    const double step = 2.5;
    for (double x = 0; x <= w; x += step) {
      final normX = (x / w).clamp(0.0, 1.0);
      double val = 0.0;
      for (int i = 0; i < 8; i++) {
        double dist = (normX - centers[i]).abs();
        if (dist > 0.5) {
          dist = 1.0 - dist;
        }
        double weight = (1.0 - (dist / 0.16)).clamp(0.0, 1.0);
        weight = weight * weight * (3.0 - 2.0 * weight);
        final v = i < values.length ? values[i] : 0.0;
        val += v * weight;
      }
      val = val.clamp(-1.0, 1.0);
      final py = midY - (val * (midY - 14.0));
      if (x == 0) {
        path.moveTo(x, py);
      } else {
        path.lineTo(x, py);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color.fromARGB(120, 0, 0, 0)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // 5. 8개 색상 포인트 노드
    for (int i = 0; i < 8; i++) {
      final px = centers[i] * w;
      final v = (i < values.length ? values[i] : 0.0).clamp(-1.0, 1.0);
      final py = midY - (v * (midY - 14.0));
      final pt = Offset(px, py);
      final isSelected = selectedBand == i;

      canvas.drawCircle(
        pt,
        isSelected ? 14.5 : 10.5,
        Paint()
          ..color = Colors.white.withValues(alpha: isSelected ? 0.36 : 0.16)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        pt,
        isSelected ? 8.0 : 7.0,
        Paint()
          ..color = const Color.fromARGB(160, 0, 0, 0)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(
        pt,
        isSelected ? 7.5 : 6.5,
        Paint()
          ..color = bandColors[i]
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        pt,
        isSelected ? 7.5 : 6.5,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ColorEqOverlayPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.selectedBand != selectedBand;
  }
}
