import 'package:flutter/material.dart';

import '../models/liquify_params.dart';
import '../models/pipeline_params.dart';
import 'control_slider.dart';

/// 포토샵 CC 2018 REA 역공학 기반 픽셀 유동화 및 얼굴 인식 위젯
class LiquifyWidget extends StatelessWidget {
  final PipelineParams params;
  final ValueChanged<void Function(PipelineParams)> onParamsChanged;
  final VoidCallback onDetectFace;
  final VoidCallback onResetLiquify;

  const LiquifyWidget({
    super.key,
    required this.params,
    required this.onParamsChanged,
    required this.onDetectFace,
    required this.onResetLiquify,
  });

  @override
  Widget build(BuildContext context) {
    final face = params.liquifyFaceParams;
    final currentTool = params.liquifyTool;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 도구 선택 바
        const Text(
          '유동화 브러시 도구 선택:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFCCCCCC)),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _toolBtn(
              tool: LiquifyToolType.warp,
              icon: Icons.pan_tool_alt,
              label: '뒤틀기 (Warp)',
              active: currentTool == LiquifyToolType.warp,
            ),
            _toolBtn(
              tool: LiquifyToolType.bloat,
              icon: Icons.add_circle_outline,
              label: '볼록 (Bloat)',
              active: currentTool == LiquifyToolType.bloat,
            ),
            _toolBtn(
              tool: LiquifyToolType.pucker,
              icon: Icons.remove_circle_outline,
              label: '오목 (Pucker)',
              active: currentTool == LiquifyToolType.pucker,
            ),
            _toolBtn(
              tool: LiquifyToolType.twirlCW,
              icon: Icons.rotate_right,
              label: '회전 (Twirl)',
              active: currentTool == LiquifyToolType.twirlCW,
            ),
            _toolBtn(
              tool: LiquifyToolType.reconstruct,
              icon: Icons.undo,
              label: '복원 (Reconstruct)',
              active: currentTool == LiquifyToolType.reconstruct,
            ),
            _toolBtn(
              tool: LiquifyToolType.smooth,
              icon: Icons.blur_on,
              label: '매끄럽게 (Smooth)',
              active: currentTool == LiquifyToolType.smooth,
            ),
            _toolBtn(
              tool: LiquifyToolType.faceAware,
              icon: Icons.face,
              label: '얼굴 인식 (Face)',
              active: currentTool == LiquifyToolType.faceAware,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 2. 브러시 크기 & 압력 슬라이더
        ControlSlider(
          label: '브러시 크기',
          value: params.liquifyBrushSize,
          min: 10.0,
          max: 250.0,
          defaultVal: 50.0,
          suffix: ' px',
          decimals: 0,
          onChanged: (v) {
            onParamsChanged((p) => p.liquifyBrushSize = v);
          },
        ),
        ControlSlider(
          label: '브러시 압력 (강도)',
          value: params.liquifyBrushPressure * 100.0,
          min: 5.0,
          max: 100.0,
          defaultVal: 50.0,
          suffix: '%',
          decimals: 0,
          onChanged: (v) {
            onParamsChanged((p) => p.liquifyBrushPressure = v / 100.0);
          },
        ),
        const SizedBox(height: 10),

        // 3. 얼굴 인식 유동화 (Face-Aware Liquify) 아코디언/섹션
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF262626),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF383838)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.face_retouching_natural, size: 16, color: Color(0xFFE8A838)),
                      SizedBox(width: 6),
                      Text(
                        '얼굴 인식 유동화 (Face-Aware)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE8A838),
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: onDetectFace,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A321E),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFE8A838)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.auto_fix_high, size: 12, color: Color(0xFFE8A838)),
                          SizedBox(width: 4),
                          Text(
                            '스마트 얼굴 감지',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE8A838),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 눈 (Eyes)
              _sectionHeader('👁️ 눈 (Eyes)'),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      face.eyeSizeLink ? '눈 크기 (양쪽 동시)' : '왼쪽 눈 크기',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFCCCCCC)),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      onParamsChanged((p) => p.liquifyFaceParams.eyeSizeLink = !p.liquifyFaceParams.eyeSizeLink);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          face.eyeSizeLink ? Icons.link : Icons.link_off,
                          size: 14,
                          color: face.eyeSizeLink ? const Color(0xFFE8A838) : Colors.grey,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          face.eyeSizeLink ? '연결됨' : '개별',
                          style: TextStyle(
                            fontSize: 10,
                            color: face.eyeSizeLink ? const Color(0xFFE8A838) : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              ControlSlider(
                label: face.eyeSizeLink ? '눈 크기' : '왼쪽 눈 크기',
                value: face.eyeSizeLeft,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) {
                    p.liquifyFaceParams.eyeSizeLeft = v;
                    if (p.liquifyFaceParams.eyeSizeLink) {
                      p.liquifyFaceParams.eyeSizeRight = v;
                    }
                  });
                },
              ),
              if (!face.eyeSizeLink)
                ControlSlider(
                  label: '오른쪽 눈 크기',
                  value: face.eyeSizeRight,
                  min: -100.0,
                  max: 100.0,
                  defaultVal: 0.0,
                  decimals: 0,
                  onChanged: (v) {
                    onParamsChanged((p) => p.liquifyFaceParams.eyeSizeRight = v);
                  },
                ),
              ControlSlider(
                label: '눈 높이',
                value: face.eyeHeightLeft,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) {
                    p.liquifyFaceParams.eyeHeightLeft = v;
                    p.liquifyFaceParams.eyeHeightRight = v;
                  });
                },
              ),
              ControlSlider(
                label: '눈 너비',
                value: face.eyeWidthLeft,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) {
                    p.liquifyFaceParams.eyeWidthLeft = v;
                    p.liquifyFaceParams.eyeWidthRight = v;
                  });
                },
              ),
              ControlSlider(
                label: '눈 기울기',
                value: face.eyeTiltLeft,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) {
                    p.liquifyFaceParams.eyeTiltLeft = v;
                    p.liquifyFaceParams.eyeTiltRight = v;
                  });
                },
              ),
              ControlSlider(
                label: '눈 사이 거리',
                value: face.eyeDistance,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.eyeDistance = v);
                },
              ),
              const SizedBox(height: 6),

              // 코 (Nose)
              _sectionHeader('👃 코 (Nose)'),
              ControlSlider(
                label: '코 높이 (상하)',
                value: face.noseHeight,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.noseHeight = v);
                },
              ),
              ControlSlider(
                label: '코 너비 (축소/확대)',
                value: face.noseWidth,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.noseWidth = v);
                },
              ),
              const SizedBox(height: 6),

              // 입 (Mouth)
              _sectionHeader('👄 입 (Mouth)'),
              ControlSlider(
                label: '미소 / 입꼬리 (Smile)',
                value: face.smile,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.smile = v);
                },
              ),
              ControlSlider(
                label: '윗입술 두께',
                value: face.upperLip,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.upperLip = v);
                },
              ),
              ControlSlider(
                label: '아랫입술 두께',
                value: face.lowerLip,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.lowerLip = v);
                },
              ),
              ControlSlider(
                label: '입 너비',
                value: face.mouthWidth,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.mouthWidth = v);
                },
              ),
              ControlSlider(
                label: '입 높이',
                value: face.mouthHeight,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.mouthHeight = v);
                },
              ),
              const SizedBox(height: 6),

              // 얼굴 모양 (Face Shape)
              _sectionHeader('👤 얼굴 모양 (Face Shape)'),
              ControlSlider(
                label: '이마 높이',
                value: face.forehead,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.forehead = v);
                },
              ),
              ControlSlider(
                label: '턱 높이 (길이)',
                value: face.chinHeight,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.chinHeight = v);
                },
              ),
              ControlSlider(
                label: '턱선 (V라인 / 사각턱)',
                value: face.jawline,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.jawline = v);
                },
              ),
              ControlSlider(
                label: '얼굴 너비 (볼/광대 축소)',
                value: face.faceWidth,
                min: -100.0,
                max: 100.0,
                defaultVal: 0.0,
                decimals: 0,
                onChanged: (v) {
                  onParamsChanged((p) => p.liquifyFaceParams.faceWidth = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 4. 하단 버튼 (초기화 및 가이드 토글)
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  onParamsChanged((p) {
                    p.liquifyFaceParams.reset();
                  });
                },
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('얼굴 수치 초기화', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFCCCCCC),
                  side: const BorderSide(color: Color(0xFF444444)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onResetLiquify,
                icon: const Icon(Icons.delete_sweep, size: 14, color: Color(0xFFFF7777)),
                label: const Text('유동화 전체 초기화', style: TextStyle(fontSize: 11, color: Color(0xFFFF7777))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF553333)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFFE0E0E0),
        ),
      ),
    );
  }

  Widget _toolBtn({
    required LiquifyToolType tool,
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return InkWell(
      onTap: () {
        onParamsChanged((p) {
          p.liquifyTool = tool;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE8A838) : const Color(0xFF333333),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? const Color(0xFFE8A838) : const Color(0xFF444444),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? const Color(0xFF141414) : const Color(0xFFE0E0E0),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? const Color(0xFF141414) : const Color(0xFFE0E0E0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
