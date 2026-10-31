import 'package:flutter/material.dart';
import 'control_slider.dart';

/// 8밴드 컬러 이퀄라이저 (SemiDarktable 정밀 호환)
/// Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta 별 HSL 독립 조절
class ColorEqualizerWidget extends StatefulWidget {
  final List<double> ceqHue;
  final List<double> ceqSat;
  final List<double> ceqBri;
  final Function(int index, double hue, double sat, double bri) onChanged;

  const ColorEqualizerWidget({
    super.key,
    required this.ceqHue,
    required this.ceqSat,
    required this.ceqBri,
    required this.onChanged,
  });

  @override
  State<ColorEqualizerWidget> createState() => _ColorEqualizerWidgetState();
}

class _ColorEqualizerWidgetState extends State<ColorEqualizerWidget> {
  int _activeBand = 0; // 0~7

  static const bandNames = ['Red', 'Orange', 'Yellow', 'Green', 'Aqua', 'Blue', 'Purple', 'Magenta'];
  static const bandColors = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF00C7BE),
    Color(0xFF007AFF),
    Color(0xFF5856D6),
    Color(0xFFAF52DE),
  ];

  @override
  Widget build(BuildContext context) {
    final curColor = bandColors[_activeBand];
    final curHue = widget.ceqHue[_activeBand];
    final curSat = widget.ceqSat[_activeBand];
    final curBri = widget.ceqBri[_activeBand];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 8개 색상환 선택 바
          SizedBox(
            height: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(8, (i) {
                final isSelected = _activeBand == i;
                final col = bandColors[i];
                final hasChanges = widget.ceqHue[i].abs() > 0.01 ||
                    widget.ceqSat[i].abs() > 0.01 ||
                    widget.ceqBri[i].abs() > 0.01;

                return GestureDetector(
                  onTap: () => setState(() => _activeBand = i),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected ? col.withOpacity(0.3) : const Color(0xFF222222),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? col : (hasChanges ? Colors.white70 : const Color(0xFF3A3A3A)),
                        width: isSelected ? 2.5 : 1.0,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 8),

          // 현재 활성 밴드 슬라이더들
          Text(
            '${bandNames[_activeBand]} 채널 미세 조절',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: curColor),
          ),

          ControlSlider(
            label: '색조 (Hue)',
            value: curHue,
            min: -1.0,
            max: 1.0,
            defaultValue: 0.0,
            onChanged: (v) => widget.onChanged(_activeBand, v, curSat, curBri),
          ),
          ControlSlider(
            label: '채도 (Saturation)',
            value: curSat,
            min: -1.0,
            max: 1.0,
            defaultValue: 0.0,
            onChanged: (v) => widget.onChanged(_activeBand, curHue, v, curBri),
          ),
          ControlSlider(
            label: '밝기 (Brightness)',
            value: curBri,
            min: -1.0,
            max: 1.0,
            defaultValue: 0.0,
            onChanged: (v) => widget.onChanged(_activeBand, curHue, curSat, v),
          ),
        ],
      ),
    );
  }
}
