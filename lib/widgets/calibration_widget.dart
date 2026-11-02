import 'package:flutter/material.dart';

import 'control_slider.dart';

/// 라이트룸 스타일 카메라 보정 (Calibration) 위젯 (Image 2 대응)
class CalibrationWidget extends StatelessWidget {
  final String processVersion;
  final double shadowsTint;
  final double redHue;
  final double redSat;
  final double greenHue;
  final double greenSat;
  final double blueHue;
  final double blueSat;

  final VoidCallback? onChangeStart;
  final VoidCallback? onAutoTurnOn;
  final VoidCallback? onChangeEnd;
  final ValueChanged<String>? onProcessVersionChanged;
  final void Function({
    double? shadowsTint,
    double? redHue,
    double? redSat,
    double? greenHue,
    double? greenSat,
    double? blueHue,
    double? blueSat,
  }) onChanged;

  const CalibrationWidget({
    super.key,
    this.processVersion = '버전 6(현재)',
    required this.shadowsTint,
    required this.redHue,
    required this.redSat,
    required this.greenHue,
    required this.greenSat,
    required this.blueHue,
    required this.blueSat,
    this.onChangeStart,
    this.onAutoTurnOn,
    this.onChangeEnd,
    this.onProcessVersionChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 프로세스 버전 선택 드롭다운
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '프로세스:',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFFBBBBBB),
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF444444)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: processVersion,
                  isDense: true,
                  dropdownColor: const Color(0xFF282828),
                  style: const TextStyle(fontSize: 11.5, color: Colors.white),
                  items: const [
                    DropdownMenuItem(
                      value: '버전 6(현재)',
                      child: Text('버전 6(현재)'),
                    ),
                    DropdownMenuItem(
                      value: '버전 5',
                      child: Text('버전 5'),
                    ),
                    DropdownMenuItem(
                      value: '버전 4',
                      child: Text('버전 4'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      onProcessVersionChanged?.call(val);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0xFF333333)),
        const SizedBox(height: 8),

        // 1. 어두운 영역 (Shadows)
        const Center(
          child: Text(
            '어두운 영역',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFCCCCCC),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _buildCalibSlider(
          label: '색조',
          value: shadowsTint,
          gradient: const LinearGradient(
            colors: [Color(0xFF2E8B57), Color(0xFF4A4A4A), Color(0xFFBA55D3)],
          ),
          onChanged: (v) => onChanged(shadowsTint: v),
        ),
        const SizedBox(height: 10),

        // 2. 빨강 기본 (Red Primary)
        const Center(
          child: Text(
            '빨강 기본',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFCCCCCC),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _buildCalibSlider(
          label: '색조',
          value: redHue,
          gradient: const LinearGradient(
            colors: [Color(0xFFC71585), Color(0xFFB22222), Color(0xFFD2691E)],
          ),
          onChanged: (v) => onChanged(redHue: v),
        ),
        _buildCalibSlider(
          label: '채도',
          value: redSat,
          gradient: const LinearGradient(
            colors: [Color(0xFF555555), Color(0xFF8B2500), Color(0xFFDC143C)],
          ),
          onChanged: (v) => onChanged(redSat: v),
        ),
        const SizedBox(height: 10),

        // 3. 초록 기본 (Green Primary)
        const Center(
          child: Text(
            '초록 기본',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFCCCCCC),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _buildCalibSlider(
          label: '색조',
          value: greenHue,
          gradient: const LinearGradient(
            colors: [Color(0xFF808000), Color(0xFF2E8B57), Color(0xFF008B8B)],
          ),
          onChanged: (v) => onChanged(greenHue: v),
        ),
        _buildCalibSlider(
          label: '채도',
          value: greenSat,
          gradient: const LinearGradient(
            colors: [Color(0xFF555555), Color(0xFF2E8B57), Color(0xFF228B22)],
          ),
          onChanged: (v) => onChanged(greenSat: v),
        ),
        const SizedBox(height: 10),

        // 4. 파랑 기본 (Blue Primary)
        const Center(
          child: Text(
            '파랑 기본',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFCCCCCC),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _buildCalibSlider(
          label: '색조',
          value: blueHue,
          gradient: const LinearGradient(
            colors: [Color(0xFF008B8B), Color(0xFF4169E1), Color(0xFF6A5ACD)],
          ),
          onChanged: (v) => onChanged(blueHue: v),
        ),
        _buildCalibSlider(
          label: '채도',
          value: blueSat,
          gradient: const LinearGradient(
            colors: [Color(0xFF555555), Color(0xFF2B4C7E), Color(0xFF1E90FF)],
          ),
          onChanged: (v) => onChanged(blueSat: v),
        ),
      ],
    );
  }

  Widget _buildCalibSlider({
    required String label,
    required double value,
    required Gradient gradient,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // 배경 그라디언트 트랙 바
            Positioned(
              left: 60,
              right: 38,
              height: 4,
              child: Container(
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ControlSlider(
              label: label,
              value: value,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              decimals: 0,
              onChangeStart: onChangeStart,
              onAutoTurnOn: onAutoTurnOn,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ],
        ),
      ],
    );
  }
}
