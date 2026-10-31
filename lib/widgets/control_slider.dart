import 'package:flutter/material.dart';

/// 전문 사진 편집용 정밀 컨트롤 슬라이더
/// 더블 클릭 시 기본값으로 리셋되며, 세밀한 수치 조절을 지원합니다.
class ControlSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final ValueChanged<double> onChanged;
  final int fractions;
  final String unit;

  const ControlSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.onChanged,
    this.fractions = 2,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    final isModified = (value - defaultValue).abs() > 0.001;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // 라벨 & 더블클릭 초기화 힌트 (유연한 너비 확장)
              Expanded(
                child: GestureDetector(
                  onDoubleTap: () => onChanged(defaultValue),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: isModified ? FontWeight.bold : FontWeight.normal,
                            color: isModified ? const Color(0xFF64B5F6) : Colors.grey[300],
                          ),
                        ),
                      ),
                      if (isModified) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFF64B5F6),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 수치 표시 (더블클릭 시 리셋)
              GestureDetector(
                onDoubleTap: () => onChanged(defaultValue),
                child: Text(
                  '${value >= 0 && min < 0 ? '+' : ''}${value.toStringAsFixed(fractions)}$unit',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: isModified ? Colors.white : Colors.grey[400],
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
              activeTrackColor: isModified ? const Color(0xFF42A5F5) : Colors.grey[600],
              inactiveTrackColor: const Color(0xFF2A2A2A),
              thumbColor: isModified ? const Color(0xFF90CAF9) : Colors.grey[400],
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
