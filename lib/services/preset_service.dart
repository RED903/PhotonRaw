import '../models/pipeline_params.dart';

/// 프리셋 모델
class Preset {
  final String id;
  final String name;
  final String description;
  final PipelineParams params;

  const Preset({
    required this.id,
    required this.name,
    required this.description,
    required this.params,
  });
}

/// 내장 프리셋 제공 서비스 (SemiDarktable 정밀 호환)
class PresetService {
  static List<Preset> getBuiltinPresets() {
    return [
      Preset(
        id: 'reset',
        name: '🔄 00 Default (기본 초기화)',
        description: '모든 보정 설정 초기화 / 원본 기본값',
        params: PipelineParams(),
      ),
      Preset(
        id: 'vivid_landscape',
        name: '🌲 Vivid Landscape (풍경 비비드)',
        description: '푸른 하늘과 싱그러운 자연의 생생하고 쨍한 색감',
        params: PipelineParams()
          ..exposureEnabled = true
          ..expEv = 0.0
          ..blackLevel = 0.02
          ..contrast = 0.2
          ..sigmoidEnabled = true
          ..sigContrast = 1.25
          ..sigShoulder = 0.15
          ..sigToe = 0.1
          ..satVibrance = 0.3
          ..satGlobal = 0.2
          ..teHighlights = -0.15
          ..teShadows = 0.15,
      ),
      Preset(
        id: 'warm_portrait',
        name: '🌸 Warm Portrait (인물 웜톤)',
        description: '자연스럽고 화사한 스킨톤 + 부드러운 하이라이트',
        params: PipelineParams()
          ..exposureEnabled = true
          ..expEv = 0.3
          ..blackLevel = -0.02
          ..contrast = -0.05
          ..wbEnabled = true
          ..wbTemperature = 6600.0
          ..wbTint = 0.06
          ..sigmoidEnabled = true
          ..sigContrast = 1.05
          ..sigSkew = 0.15
          ..sigShoulder = 0.35
          ..sigToe = 0.05
          ..satVibrance = 0.1
          ..satGlobal = 0.05
          ..teHighlights = -0.2
          ..teShadows = 0.1,
      ),
      Preset(
        id: 'modern_film',
        name: '🎞️ Modern Film (필름 룩)',
        description: '부드러운 하이라이트 페이드 + 따뜻한 골드 섀도우',
        params: PipelineParams()
          ..exposureEnabled = true
          ..expEv = 0.15
          ..blackLevel = 0.05
          ..contrast = 0.1
          ..wbEnabled = true
          ..wbTemperature = 6200.0
          ..wbTint = 0.04
          ..sigmoidEnabled = true
          ..sigContrast = 1.15
          ..sigSkew = 0.1
          ..sigShoulder = 0.2
          ..sigToe = 0.15
          ..satVibrance = -0.05
          ..satGlobal = -0.1
          ..teShadows = 0.2,
      ),
      Preset(
        id: 'cinematic_moody',
        name: '🎬 Cinematic Moody (시네마틱)',
        description: '깊은 섀도우 틸/오렌지 색감 + 짙은 시네마 분위기',
        params: PipelineParams()
          ..exposureEnabled = true
          ..expEv = -0.2
          ..blackLevel = 0.08
          ..contrast = 0.25
          ..wbEnabled = true
          ..wbTemperature = 5800.0
          ..wbTint = -0.02
          ..sigmoidEnabled = true
          ..sigContrast = 1.3
          ..sigSkew = -0.1
          ..sigShoulder = 0.1
          ..sigToe = 0.2
          ..teHighlights = -0.25
          ..teShadows = -0.1
          ..satVibrance = 0.15
          ..satGlobal = 0.1,
      ),
      Preset(
        id: 'bw_fineart',
        name: '🖤 B&W Fine Art (흑백 파인아트)',
        description: '강렬한 대비와 깊은 톤의 클래식 흑백',
        params: PipelineParams()
          ..exposureEnabled = true
          ..expEv = 0.1
          ..blackLevel = 0.06
          ..contrast = 0.35
          ..colorZonesEnabled = true
          ..satGlobal = -1.0
          ..satVibrance = 0.0
          ..sigmoidEnabled = true
          ..sigContrast = 1.4
          ..sigShoulder = 0.2
          ..sigToe = 0.2
          ..teHighlights = 0.1
          ..teShadows = -0.15,
      ),
    ];
  }
}
