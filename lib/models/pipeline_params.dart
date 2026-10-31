import 'dart:convert';

/// PhotonRaw 파이프라인 파라미터 상태
/// SemiDarktable 및 SemiLightroom과 완벽하게 호환되는 속성 구조를 가집니다.
class PipelineParams {
  // 기하학 / 방향
  bool orientationEnabled = true;
  int rotate90 = 0; // 0, 90, 180, 270
  bool flipH = false;
  bool flipV = false;
  double angle = 0.0; // -45.0 ~ 45.0도 (수평선 미세 보정)

  // 크롭
  bool cropEnabled = false;
  double cropLeft = 0.0;
  double cropTop = 0.0;
  double cropRight = 1.0;
  double cropBottom = 1.0;

  // 노출 (Exposure)
  bool exposureEnabled = true;
  double exposureEv = 0.0; // -5.0 ~ 5.0 EV
  double blackLevel = 0.0; // -0.2 ~ 0.2
  double contrast = 0.0; // -1.0 ~ 1.0

  // 화이트 밸런스 / 색상 (White Balance / Color)
  bool whiteBalanceEnabled = true;
  double temperature = 0.0; // -100.0 ~ 100.0 (Cool <-> Warm)
  double tint = 0.0; // -100.0 ~ 100.0 (Green <-> Magenta)
  double vibrance = 0.0; // -100.0 ~ 100.0
  double saturation = 0.0; // -100.0 ~ 100.0

  // 하이라이트 & 섀도우 (Highlights / Shadows)
  bool toneDetailEnabled = true;
  double highlights = 0.0; // -100.0 ~ 100.0
  double shadows = 0.0; // -100.0 ~ 100.0

  // 시그모이드 톤 매핑 (Sigmoid Tone Mapping)
  bool sigmoidEnabled = true;
  double sigContrast = 1.0; // 0.5 ~ 2.5
  double sigSkew = 0.0; // -1.0 ~ 1.0
  double sigShoulder = 0.0; // -1.0 ~ 1.0
  double sigToe = 0.0; // -1.0 ~ 1.0

  // 톤 커브 (Tone Curve 제어점 목록: [0.0 ~ 1.0])
  bool toneCurveEnabled = false;
  List<CurvePoint> rgbCurve = [const CurvePoint(0.0, 0.0), const CurvePoint(1.0, 1.0)];
  List<CurvePoint> rCurve = [const CurvePoint(0.0, 0.0), const CurvePoint(1.0, 1.0)];
  List<CurvePoint> gCurve = [const CurvePoint(0.0, 0.0), const CurvePoint(1.0, 1.0)];
  List<CurvePoint> bCurve = [const CurvePoint(0.0, 0.0), const CurvePoint(1.0, 1.0)];

  PipelineParams();

  /// 기본값으로 복제
  PipelineParams clone() {
    final copy = PipelineParams();
    copy.orientationEnabled = orientationEnabled;
    copy.rotate90 = rotate90;
    copy.flipH = flipH;
    copy.flipV = flipV;
    copy.angle = angle;

    copy.cropEnabled = cropEnabled;
    copy.cropLeft = cropLeft;
    copy.cropTop = cropTop;
    copy.cropRight = cropRight;
    copy.cropBottom = cropBottom;

    copy.exposureEnabled = exposureEnabled;
    copy.exposureEv = exposureEv;
    copy.blackLevel = blackLevel;
    copy.contrast = contrast;

    copy.whiteBalanceEnabled = whiteBalanceEnabled;
    copy.temperature = temperature;
    copy.tint = tint;
    copy.vibrance = vibrance;
    copy.saturation = saturation;

    copy.toneDetailEnabled = toneDetailEnabled;
    copy.highlights = highlights;
    copy.shadows = shadows;

    copy.sigmoidEnabled = sigmoidEnabled;
    copy.sigContrast = sigContrast;
    copy.sigSkew = sigSkew;
    copy.sigShoulder = sigShoulder;
    copy.sigToe = sigToe;

    copy.toneCurveEnabled = toneCurveEnabled;
    copy.rgbCurve = List.from(rgbCurve);
    copy.rCurve = List.from(rCurve);
    copy.gCurve = List.from(gCurve);
    copy.bCurve = List.from(bCurve);

    return copy;
  }

  /// JSON 맵으로 직렬화 (프리셋 저장용)
  Map<String, dynamic> toJson() {
    return {
      'rotate_90': rotate90,
      'flip_h': flipH,
      'flip_v': flipV,
      'angle': angle,
      'exposure_ev': exposureEv,
      'black_level': blackLevel,
      'contrast': contrast,
      'temperature': temperature,
      'tint': tint,
      'vibrance': vibrance,
      'saturation': saturation,
      'highlights': highlights,
      'shadows': shadows,
      'sigmoid_enabled': sigmoidEnabled,
      'sig_contrast': sigContrast,
      'sig_skew': sigSkew,
      'sig_shoulder': sigShoulder,
      'sig_toe': sigToe,
      'tone_curve_enabled': toneCurveEnabled,
      'rgb_curve': rgbCurve.map((p) => [p.x, p.y]).toList(),
    };
  }

  /// JSON에서 복원 (프리셋 불러오기용)
  factory PipelineParams.fromJson(Map<String, dynamic> json) {
    final p = PipelineParams();
    p.rotate90 = (json['rotate_90'] as num?)?.toInt() ?? 0;
    p.flipH = json['flip_h'] as bool? ?? false;
    p.flipV = json['flip_v'] as bool? ?? false;
    p.angle = (json['angle'] as num?)?.toDouble() ?? 0.0;
    p.exposureEv = (json['exposure_ev'] as num?)?.toDouble() ?? 0.0;
    p.blackLevel = (json['black_level'] as num?)?.toDouble() ?? 0.0;
    p.contrast = (json['contrast'] as num?)?.toDouble() ?? 0.0;
    p.temperature = (json['temperature'] as num?)?.toDouble() ?? 0.0;
    p.tint = (json['tint'] as num?)?.toDouble() ?? 0.0;
    p.vibrance = (json['vibrance'] as num?)?.toDouble() ?? 0.0;
    p.saturation = (json['saturation'] as num?)?.toDouble() ?? 0.0;
    p.highlights = (json['highlights'] as num?)?.toDouble() ?? 0.0;
    p.shadows = (json['shadows'] as num?)?.toDouble() ?? 0.0;
    p.sigmoidEnabled = json['sigmoid_enabled'] as bool? ?? true;
    p.sigContrast = (json['sig_contrast'] as num?)?.toDouble() ?? 1.0;
    p.sigSkew = (json['sig_skew'] as num?)?.toDouble() ?? 0.0;
    p.sigShoulder = (json['sig_shoulder'] as num?)?.toDouble() ?? 0.0;
    p.sigToe = (json['sig_toe'] as num?)?.toDouble() ?? 0.0;
    p.toneCurveEnabled = json['tone_curve_enabled'] as bool? ?? false;

    if (json['rgb_curve'] != null) {
      final list = json['rgb_curve'] as List;
      p.rgbCurve = list.map((item) {
        final pair = item as List;
        return CurvePoint((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
      }).toList();
    }
    return p;
  }
}

/// 톤 커브 제어점 (0.0 ~ 1.0)
class CurvePoint {
  final double x;
  final double y;
  const CurvePoint(this.x, this.y);
}
