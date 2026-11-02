import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'control_slider.dart';

enum ColorGradingViewMode {
  threeWay,
  midtones,
  shadows,
  highlights,
  global,
}

/// 라이트룸 스타일 색 보정 (Color Grading / Split Toning) 위젯
class ColorGradingWidget extends StatefulWidget {
  final double midtonesHue;
  final double midtonesSat;
  final double midtonesLum;

  final double shadowsHue;
  final double shadowsSat;
  final double shadowsLum;

  final double highlightsHue;
  final double highlightsSat;
  final double highlightsLum;

  final double globalHue;
  final double globalSat;
  final double globalLum;

  final double blending;
  final double balance;

  final VoidCallback? onChangeStart;
  final VoidCallback? onAutoTurnOn;
  final VoidCallback? onChangeEnd;
  final void Function({
    double? midHue,
    double? midSat,
    double? midLum,
    double? shadHue,
    double? shadSat,
    double? shadLum,
    double? highHue,
    double? highSat,
    double? highLum,
    double? globHue,
    double? globSat,
    double? globLum,
    double? blending,
    double? balance,
  }) onChanged;

  const ColorGradingWidget({
    super.key,
    required this.midtonesHue,
    required this.midtonesSat,
    required this.midtonesLum,
    required this.shadowsHue,
    required this.shadowsSat,
    required this.shadowsLum,
    required this.highlightsHue,
    required this.highlightsSat,
    required this.highlightsLum,
    required this.globalHue,
    required this.globalSat,
    required this.globalLum,
    required this.blending,
    required this.balance,
    this.onChangeStart,
    this.onAutoTurnOn,
    this.onChangeEnd,
    required this.onChanged,
  });

  @override
  State<ColorGradingWidget> createState() => _ColorGradingWidgetState();
}

class _ColorGradingWidgetState extends State<ColorGradingWidget> {
  ColorGradingViewMode _viewMode = ColorGradingViewMode.threeWay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 상단 뷰 모드 툴바: [조정 :] [ 3-Way 전체 보기 ] [ 중간 톤 ] [ 어두운 영역 ] [ 밝은 영역 ] [ 전체 ]
        _buildModeSelector(),
        const SizedBox(height: 10),

        if (_viewMode == ColorGradingViewMode.threeWay) ...[
          // 중간 톤
          _buildWheelSection(
            title: '중간 톤',
            hue: widget.midtonesHue,
            sat: widget.midtonesSat,
            lum: widget.midtonesLum,
            size: 130,
            onWheelChanged: (h, s) => widget.onChanged(midHue: h, midSat: s),
            onLumChanged: (l) => widget.onChanged(midLum: l),
            onReset: () => widget.onChanged(midHue: 0, midSat: 0, midLum: 0),
          ),
          const SizedBox(height: 12),
          // 어두운 영역 & 밝은 영역 나란히 또는 세로 배치
          _buildWheelSection(
            title: '어두운 영역',
            hue: widget.shadowsHue,
            sat: widget.shadowsSat,
            lum: widget.shadowsLum,
            size: 130,
            onWheelChanged: (h, s) => widget.onChanged(shadHue: h, shadSat: s),
            onLumChanged: (l) => widget.onChanged(shadLum: l),
            onReset: () => widget.onChanged(shadHue: 0, shadSat: 0, shadLum: 0),
          ),
          const SizedBox(height: 12),
          _buildWheelSection(
            title: '밝은 영역',
            hue: widget.highlightsHue,
            sat: widget.highlightsSat,
            lum: widget.highlightsLum,
            size: 130,
            onWheelChanged: (h, s) => widget.onChanged(highHue: h, highSat: s),
            onLumChanged: (l) => widget.onChanged(highLum: l),
            onReset: () => widget.onChanged(highHue: 0, highSat: 0, highLum: 0),
          ),
        ] else if (_viewMode == ColorGradingViewMode.midtones) ...[
          _buildSingleExpandedWheel(
            title: '중간 톤 (Midtones)',
            hue: widget.midtonesHue,
            sat: widget.midtonesSat,
            lum: widget.midtonesLum,
            onWheelChanged: (h, s) => widget.onChanged(midHue: h, midSat: s),
            onLumChanged: (l) => widget.onChanged(midLum: l),
            onReset: () => widget.onChanged(midHue: 0, midSat: 0, midLum: 0),
          ),
        ] else if (_viewMode == ColorGradingViewMode.shadows) ...[
          _buildSingleExpandedWheel(
            title: '어두운 영역 (Shadows)',
            hue: widget.shadowsHue,
            sat: widget.shadowsSat,
            lum: widget.shadowsLum,
            onWheelChanged: (h, s) => widget.onChanged(shadHue: h, shadSat: s),
            onLumChanged: (l) => widget.onChanged(shadLum: l),
            onReset: () => widget.onChanged(shadHue: 0, shadSat: 0, shadLum: 0),
          ),
        ] else if (_viewMode == ColorGradingViewMode.highlights) ...[
          _buildSingleExpandedWheel(
            title: '밝은 영역 (Highlights)',
            hue: widget.highlightsHue,
            sat: widget.highlightsSat,
            lum: widget.highlightsLum,
            onWheelChanged: (h, s) => widget.onChanged(highHue: h, highSat: s),
            onLumChanged: (l) => widget.onChanged(highLum: l),
            onReset: () => widget.onChanged(highHue: 0, highSat: 0, highLum: 0),
          ),
        ] else if (_viewMode == ColorGradingViewMode.global) ...[
          _buildSingleExpandedWheel(
            title: '전체 (Global)',
            hue: widget.globalHue,
            sat: widget.globalSat,
            lum: widget.globalLum,
            onWheelChanged: (h, s) => widget.onChanged(globHue: h, globSat: s),
            onLumChanged: (l) => widget.onChanged(globLum: l),
            onReset: () => widget.onChanged(globHue: 0, globSat: 0, globLum: 0),
          ),
        ],

        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFF333333)),
        const SizedBox(height: 8),

        // 하단 슬라이더: 혼합 (0 ~ 100, 기본 50) & 균형 (-100 ~ 100, 기본 0)
        ControlSlider(
          label: '혼합 (Blending)',
          value: widget.blending,
          min: 0.0,
          max: 100.0,
          defaultVal: 50.0,
          decimals: 0,
          onChangeStart: widget.onChangeStart,
          onAutoTurnOn: widget.onAutoTurnOn,
          onChanged: (v) => widget.onChanged(blending: v),
          onChangeEnd: widget.onChangeEnd,
        ),
        ControlSlider(
          label: '균형 (Balance)',
          value: widget.balance,
          min: -100.0,
          max: 100.0,
          defaultVal: 0.0,
          decimals: 0,
          onChangeStart: widget.onChangeStart,
          onAutoTurnOn: widget.onAutoTurnOn,
          onChanged: (v) => widget.onChanged(balance: v),
          onChangeEnd: widget.onChangeEnd,
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        const Text(
          '조정 :',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF999999),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        _modeButton(
          mode: ColorGradingViewMode.threeWay,
          tooltip: '3-Way 전체 보기 (중간톤 / 어두운 영역 / 밝은 영역)',
          icon: Icons.grain, // 3 concentric / grouped dots
        ),
        const SizedBox(width: 4),
        Container(width: 1, height: 14, color: const Color(0xFF444444)),
        const SizedBox(width: 4),
        _modeButton(
          mode: ColorGradingViewMode.midtones,
          tooltip: '중간 톤 (Midtones)',
          icon: Icons.circle,
        ),
        _modeButton(
          mode: ColorGradingViewMode.shadows,
          tooltip: '어두운 영역 (Shadows)',
          icon: Icons.radio_button_unchecked,
        ),
        _modeButton(
          mode: ColorGradingViewMode.highlights,
          tooltip: '밝은 영역 (Highlights)',
          icon: Icons.brightness_high,
        ),
        const SizedBox(width: 4),
        Container(width: 1, height: 14, color: const Color(0xFF444444)),
        const SizedBox(width: 4),
        _modeButton(
          mode: ColorGradingViewMode.global,
          tooltip: '전체 (Global)',
          icon: Icons.tonality,
        ),
      ],
    );
  }

  Widget _modeButton({
    required ColorGradingViewMode mode,
    required String tooltip,
    required IconData icon,
  }) {
    final selected = _viewMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => setState(() => _viewMode = mode),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3A3A3A) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: selected
                ? Border.all(color: const Color(0xFFE8A838), width: 1)
                : null,
          ),
          child: Icon(
            icon,
            size: 15,
            color: selected ? const Color(0xFFE8A838) : const Color(0xFFAAAAAA),
          ),
        ),
      ),
    );
  }

  Widget _buildWheelSection({
    required String title,
    required double hue,
    required double sat,
    required double lum,
    required double size,
    required void Function(double h, double s) onWheelChanged,
    required ValueChanged<double> onLumChanged,
    required VoidCallback onReset,
  }) {
    final curColor = _hslToColor(hue, sat);
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFFCCCCCC),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ColorWheel(
              hue: hue,
              sat: sat,
              size: size,
              onChangeStart: widget.onChangeStart,
              onAutoTurnOn: widget.onAutoTurnOn,
              onChanged: onWheelChanged,
              onChangeEnd: widget.onChangeEnd,
              onReset: onReset,
            ),
            const SizedBox(width: 8),
            // 우측 작은 프리뷰 및 더블클릭 리셋 원
            Tooltip(
              message: '더블클릭하여 초기화 (H: ${hue.toStringAsFixed(0)}°, S: ${sat.toStringAsFixed(0)}%)',
              child: InkWell(
                onDoubleTap: onReset,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: sat > 0 ? curColor : const Color(0xFF333333),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF666666), width: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 휠 하단 휘도(Luminance) 슬라이더
        SizedBox(
          width: size + 30,
          child: ControlSlider(
            label: '휘도',
            value: lum,
            min: -100.0,
            max: 100.0,
            defaultVal: 0.0,
            decimals: 0,
            onChangeStart: widget.onChangeStart,
            onAutoTurnOn: widget.onAutoTurnOn,
            onChanged: onLumChanged,
            onChangeEnd: widget.onChangeEnd,
          ),
        ),
      ],
    );
  }

  Widget _buildSingleExpandedWheel({
    required String title,
    required double hue,
    required double sat,
    required double lum,
    required void Function(double h, double s) onWheelChanged,
    required ValueChanged<double> onLumChanged,
    required VoidCallback onReset,
  }) {
    final curColor = _hslToColor(hue, sat);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFE8A838),
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF888888)),
              tooltip: '기본값으로 초기화',
              onPressed: onReset,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: ColorWheel(
            hue: hue,
            sat: sat,
            size: 180,
            onChangeStart: widget.onChangeStart,
            onAutoTurnOn: widget.onAutoTurnOn,
            onChanged: onWheelChanged,
            onChangeEnd: widget.onChangeEnd,
            onReset: onReset,
          ),
        ),
        const SizedBox(height: 10),
        ControlSlider(
          label: '색상 (Hue)',
          value: hue,
          min: 0.0,
          max: 360.0,
          defaultVal: 0.0,
          decimals: 0,
          suffix: '°',
          onChangeStart: widget.onChangeStart,
          onAutoTurnOn: widget.onAutoTurnOn,
          onChanged: (v) => onWheelChanged(v, sat),
          onChangeEnd: widget.onChangeEnd,
        ),
        ControlSlider(
          label: '채도 (Saturation)',
          value: sat,
          min: 0.0,
          max: 100.0,
          defaultVal: 0.0,
          decimals: 0,
          onChangeStart: widget.onChangeStart,
          onAutoTurnOn: widget.onAutoTurnOn,
          onChanged: (v) => onWheelChanged(hue, v),
          onChangeEnd: widget.onChangeEnd,
        ),
        ControlSlider(
          label: '휘도 (Luminance)',
          value: lum,
          min: -100.0,
          max: 100.0,
          defaultVal: 0.0,
          decimals: 0,
          onChangeStart: widget.onChangeStart,
          onAutoTurnOn: widget.onAutoTurnOn,
          onChanged: onLumChanged,
          onChangeEnd: widget.onChangeEnd,
        ),
      ],
    );
  }

  Color _hslToColor(double h, double s) {
    if (s <= 0.0) return const Color(0xFF888888);
    return HSLColor.fromAHSL(1.0, (h % 360.0), (s / 100.0).clamp(0.0, 1.0), 0.5).toColor();
  }
}

/// 원형 컬러 휠 컴포넌트
class ColorWheel extends StatefulWidget {
  final double hue;
  final double sat;
  final double size;
  final VoidCallback? onChangeStart;
  final VoidCallback? onAutoTurnOn;
  final VoidCallback? onChangeEnd;
  final void Function(double hue, double sat) onChanged;
  final VoidCallback onReset;

  const ColorWheel({
    super.key,
    required this.hue,
    required this.sat,
    this.size = 140,
    this.onChangeStart,
    this.onAutoTurnOn,
    this.onChangeEnd,
    required this.onChanged,
    required this.onReset,
  });

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  DateTime? _lastTapTime;

  void _handleTouch(Offset localPos, double radius) {
    final dx = localPos.dx - radius;
    final dy = localPos.dy - radius;
    final dist = math.sqrt(dx * dx + dy * dy);
    final sat = (dist / radius).clamp(0.0, 1.0) * 100.0;
    var rad = math.atan2(dy, dx);
    var deg = rad * 180.0 / math.pi;
    if (deg < 0) deg += 360.0;
    widget.onChanged(deg, sat);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final r = s / 2.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: widget.onReset,
      onPanDown: (details) {
        final now = DateTime.now();
        if (_lastTapTime != null && now.difference(_lastTapTime!).inMilliseconds < 400) {
          widget.onReset();
          _lastTapTime = null;
          return;
        }
        _lastTapTime = now;
        widget.onAutoTurnOn?.call();
        widget.onChangeStart?.call();
        _handleTouch(details.localPosition, r);
      },
      onPanUpdate: (details) {
        _handleTouch(details.localPosition, r);
      },
      onPanEnd: (_) => widget.onChangeEnd?.call(),
      onPanCancel: () => widget.onChangeEnd?.call(),
      child: SizedBox(
        width: s,
        height: s,
        child: CustomPaint(
          size: Size(s, s),
          painter: _ColorWheelPainter(
            hue: widget.hue,
            sat: widget.sat,
          ),
        ),
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  final double hue;
  final double sat;

  _ColorWheelPainter({
    required this.hue,
    required this.sat,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    final radius = math.min(cx, cy) - 2.0;

    // 1. 색상환 (스윕 그라디언트)
    final sweep = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF0000), // Red 0°
          Color(0xFFFFFF00), // Yellow 60°
          Color(0xFF00FF00), // Green 120°
          Color(0xFF00FFFF), // Cyan 180°
          Color(0xFF0000FF), // Blue 240°
          Color(0xFFFF00FF), // Magenta 300°
          Color(0xFFFF0000), // Red 360°
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));

    canvas.drawCircle(Offset(cx, cy), radius, sweep);

    // 2. 중심 채도 감쇄 (중심으로 갈수록 중간 회색 0xFF555555)
    final desat = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF555555),
          const Color(0xFF555555).withOpacity(0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));

    canvas.drawCircle(Offset(cx, cy), radius, desat);

    // 3. 외곽 원형 테두리
    final borderPaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), radius, borderPaint);

    // 4. 중앙 중립 기준 점
    final centerDotPaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(cx, cy), 3.0, centerDotPaint);

    // 5. 현재 선택된 (Hue, Sat) 조작 점 (동심원 링)
    final selDist = (sat / 100.0).clamp(0.0, 1.0) * radius;
    final rad = hue * math.pi / 180.0;
    final selX = cx + selDist * math.cos(rad);
    final selY = cy + selDist * math.sin(rad);

    final selFill = Paint()
      ..color = const Color(0xFF222222)
      ..style = PaintingStyle.fill;
    final selBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(Offset(selX, selY), 5.5, selFill);
    canvas.drawCircle(Offset(selX, selY), 5.5, selBorder);
    canvas.drawCircle(
      Offset(selX, selY),
      2.0,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return oldDelegate.hue != hue || oldDelegate.sat != sat;
  }
}
