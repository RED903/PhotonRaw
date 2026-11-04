import 'dart:convert';
import 'liquify_params.dart';

/// 스팟 리터칭 한 점 또는 자유 곡선 브러시 스트로크 (모두 0~1 정규화 좌표)
class Spot {
  double x;
  double y;
  double r;
  double srcX;
  double srcY;
  /// 브러시로 드래그하여 칠한 궤적 좌표 목록 (비어있거나 1개면 단일 원형 스팟)
  List<List<double>> path;

  Spot({
    required this.x,
    required this.y,
    this.r = 0.02,
    required this.srcX,
    required this.srcY,
    List<List<double>>? path,
  }) : path = path ?? [];

  Spot clone() => Spot(
        x: x,
        y: y,
        r: r,
        srcX: srcX,
        srcY: srcY,
        path: [
          for (final pt in path) [pt[0], pt[1]],
        ],
      );

  Map<String, dynamic> toMap() => {
        'x': x,
        'y': y,
        'r': r,
        'src_x': srcX,
        'src_y': srcY,
        if (path.isNotEmpty)
          'path': [
            for (final pt in path) [pt[0], pt[1]],
          ],
      };

  factory Spot.fromMap(Map m) {
    final x = _d(m['x'], 0.5);
    final y = _d(m['y'], 0.5);
    final rawPath = m['path'];
    final parsedPath = <List<double>>[];
    if (rawPath is List) {
      for (final e in rawPath) {
        if (e is List && e.length >= 2) {
          parsedPath.add([_d(e[0], x), _d(e[1], y)]);
        }
      }
    }
    return Spot(
      x: x,
      y: y,
      r: _d(m['r'], 0.02),
      srcX: _d(m['src_x'], x + 0.03),
      srcY: _d(m['src_y'], y),
      path: parsedPath,
    );
  }
}

/// 적목 제거(Red-Eye) 한 점 (0~1 정규화 좌표)
class RedEyeSpot {
  double x;
  double y;
  double r;
  double strength;

  RedEyeSpot({
    required this.x,
    required this.y,
    this.r = 0.025,
    this.strength = 0.85,
  });

  RedEyeSpot clone() => RedEyeSpot(x: x, y: y, r: r, strength: strength);

  Map<String, dynamic> toMap() => {
        'x': x,
        'y': y,
        'r': r,
        'strength': strength,
      };

  factory RedEyeSpot.fromMap(Map m) => RedEyeSpot(
        x: _d(m['x'], 0.5),
        y: _d(m['y'], 0.5),
        r: _d(m['r'], 0.025),
        strength: _d(m['strength'], 0.85),
      );
}

double _d(dynamic v, double def) => v is num ? v.toDouble() : def;
bool _b(dynamic v, bool def) => v is bool ? v : def;

List<double> _list8(dynamic v) {
  if (v is List && v.length == 8) {
    return [for (final e in v) _d(e, 0.0)];
  }
  return List<double>.filled(8, 0.0);
}

/// 곡선 키 (RGB 마스터 + R/G/B 채널)
const List<String> kCurveKeys = ['rgb', 'r', 'g', 'b'];

Map<String, List<List<double>>> _identityCurves() => {
      for (final k in kCurveKeys)
        k: [
          [0.0, 0.0],
          [1.0, 1.0]
        ],
    };

/// SemiDarktable `PipelineParams`와 1:1 대응되는 보정 파라미터.
/// 직렬화 키는 원본(Python)과 동일하여 원본 프리셋 JSON을 그대로 읽을 수 있습니다.
class PipelineParams {
  // 기하학 / 방향
  int rotate90 = 0; // 0, 90, 180, 270
  bool flipH = false;
  bool flipV = false;
  double angle = 0.0; // -45 ~ 45
  bool cropEnabled = false;
  List<double> cropRect = [0.0, 0.0, 1.0, 1.0]; // x, y, w, h (0~1)

  // 톤 커브
  bool toneCurveEnabled = false;
  Map<String, List<List<double>>> toneCurvePoints = _identityCurves();

  // 노출
  bool exposureEnabled = false;
  double expEv = 0.0;
  double expBlackLevel = 0.0;
  double expContrast = 0.0;

  // 시그모이드
  bool sigmoidEnabled = false;
  double sigContrast = 1.0;
  double sigSkew = 0.0;
  double sigShoulder = 0.0;
  double sigToe = 0.0;

  // 톤 이퀄라이저 (EV)
  bool toneEqualizerEnabled = false;
  double teBlacks = 0.0;
  double teShadows = 0.0;
  double teMidtones = 0.0;
  double teHighlights = 0.0;
  double teWhites = 0.0;

  // 하이라이트 복원
  bool highlightEnabled = false;
  double hlRecovery = 0.0;
  double hlCompress = 0.0;

  // 화이트 밸런스
  bool wbEnabled = false;
  double wbTemperature = 6500.0;
  double wbTint = 0.0;
  double wbAsShotTemp = 6500.0;
  double wbAsShotTint = 0.0;

  // 채도 & 생동감
  bool colorZonesEnabled = false;
  double satGlobal = 0.0;
  double satVibrance = 0.0;

  // 8밴드 컬러 이퀄라이저
  bool colorEqualizerEnabled = false;
  List<double> ceqHue = List<double>.filled(8, 0.0);
  List<double> ceqSat = List<double>.filled(8, 0.0);
  List<double> ceqBri = List<double>.filled(8, 0.0);

  // 컬러 밸런스 RGB
  bool colorBalanceEnabled = false;
  double cbShadowsR = 0.0;
  double cbMidtonesG = 0.0;
  double cbMidtonesB = 0.0;
  double cbHighlightsR = 0.0;

  // 색 보정 (Color Grading / Split Toning - 3-Way & Global)
  bool colorGradingEnabled = false;
  double cgMidtonesHue = 0.0; // 0 ~ 360
  double cgMidtonesSat = 0.0; // 0 ~ 100
  double cgMidtonesLum = 0.0; // -100 ~ 100
  double cgShadowsHue = 0.0;
  double cgShadowsSat = 0.0;
  double cgShadowsLum = 0.0;
  double cgHighlightsHue = 0.0;
  double cgHighlightsSat = 0.0;
  double cgHighlightsLum = 0.0;
  double cgGlobalHue = 0.0;
  double cgGlobalSat = 0.0;
  double cgGlobalLum = 0.0;
  double cgBlending = 50.0; // 0 ~ 100 (혼합)
  double cgBalance = 0.0; // -100 ~ 100 (균형)

  // 보정 (Calibration - Camera Calibration)
  bool calibrationEnabled = false;
  String calibVersion = '버전 6(현재)';
  double calibShadowsTint = 0.0; // -100 ~ 100 (그린 <-> 마젠타)
  double calibRedHue = 0.0; // -100 ~ 100
  double calibRedSat = 0.0; // -100 ~ 100
  double calibGreenHue = 0.0; // -100 ~ 100
  double calibGreenSat = 0.0; // -100 ~ 100
  double calibBlueHue = 0.0; // -100 ~ 100
  double calibBlueSat = 0.0; // -100 ~ 100

  // 렌즈 프로필 교정 (Lens Profile Correction - Lensfun / Darktable DB)
  bool lensCorrectionEnabled = false;
  String lensProfileMake = '';
  String lensProfileModel = '';
  double lensDistortionScale = 100.0; // 0 ~ 200%
  double lensVignetteScale = 100.0; // 0 ~ 200%
  bool lensTcaEnabled = true;
  double lensManualDistortion = 0.0; // -100 ~ 100
  double lensManualVignette = 0.0; // -100 ~ 100
  double lensManualTcaR = 0.0; // -50 ~ 50
  double lensManualTcaB = 0.0; // -50 ~ 50

  // 디테일 모듈
  bool sharpenEnabled = false;
  double shAmount = 0.0;

  bool localContrastEnabled = false;
  double lcDetail = 0.0;
  double lcClarity = 0.0;

  bool denoiseEnabled = false;
  double dnStrength = 0.0; // 휘도(밝기) 노이즈 억제 강도
  double dnColor = 0.0; // 색(크로마) 노이즈 억제 강도
  double dnDetail = 0.5; // 디테일/엣지 보존 정도 (높을수록 윤곽 보존)

  bool blurEnabled = false;
  double blurRadius = 0.0;

  bool grainEnabled = false;
  double grAmount = 0.0; // 입자 강도
  double grSize = 0.25; // 입자 크기
  double grRoughness = 0.5; // 거칠기 (낮음: 부드러운 덩어리, 높음: 날카로운 입자)

  bool vignetteEnabled = false;
  double vgAmount = 0.0; // -1(어둡게) ~ +1(밝게)
  double vgMidpoint = 0.5; // 비네팅이 시작되는 지점 (높을수록 가장자리에만 적용)
  double vgFeather = 0.5; // 경계 부드러움
  double vgRoundness = 0.0; // -1(직사각형) ~ +1(원형)
  double vgHighlights = 0.0; // 어둡게 할 때 하이라이트 보호 정도

  // 디헤이즈 / 디프린지 / 스팟
  bool dehazeEnabled = false;
  double dhStrength = 0.0;

  bool defringeEnabled = false;
  double dfStrength = 0.0;
  double dfThreshold = 0.10;

  bool spotEnabled = false;
  List<Spot> spots = [];

  bool redEyeEnabled = false;
  List<RedEyeSpot> redEyes = [];

  // 픽셀 유동화 (Liquify & Face-Aware)
  bool liquifyEnabled = false;
  LiquifyToolType liquifyTool = LiquifyToolType.warp;
  double liquifyBrushSize = 50.0;
  double liquifyBrushPressure = 0.5;
  bool liquifyShowGuide = true;
  bool liquifyFaceDetected = false;
  FaceLandmarks liquifyLandmarks = FaceLandmarks();
  FaceAwareParams liquifyFaceParams = FaceAwareParams();
  LiquifyDisplacementGrid liquifyGrid = LiquifyDisplacementGrid();

  // 뷰
  bool splitViewEnabled = false;
  double splitPosition = 0.5;

  PipelineParams();

  PipelineParams clone() => PipelineParams.fromMap(toMap());

  /// 변형 세팅(회전, 플립, 각도, 크롭 등 기하학)을 제외한 현상 설정 맵 복사
  Map<String, dynamic> toDevelopmentMap({bool excludeTransform = true}) {
    final m = toMap();
    if (excludeTransform) {
      m.remove('rotate_90');
      m.remove('flip_h');
      m.remove('flip_v');
      m.remove('angle');
      m.remove('crop_enabled');
      m.remove('crop_rect');
      m.remove('split_view_enabled');
      m.remove('split_position');
    }
    return m;
  }

  /// 다른 PipelineParams에서 변형 세팅을 제외한 현상 설정만 덮어쓰기
  void copyDevelopmentFrom(PipelineParams source, {bool excludeTransform = true}) {
    final m = source.toDevelopmentMap(excludeTransform: excludeTransform);
    applyMap(m);
  }

  Map<String, dynamic> toMap() => {
        'rotate_90': rotate90,
        'flip_h': flipH,
        'flip_v': flipV,
        'angle': angle,
        'crop_enabled': cropEnabled,
        'crop_rect': List<double>.from(cropRect),
        'tone_curve_enabled': toneCurveEnabled,
        'tone_curve_points': {
          for (final e in toneCurvePoints.entries)
            e.key: [
              for (final pt in e.value) [pt[0], pt[1]]
            ],
        },
        'exposure_enabled': exposureEnabled,
        'exp_ev': expEv,
        'exp_black_level': expBlackLevel,
        'exp_contrast': expContrast,
        'sigmoid_enabled': sigmoidEnabled,
        'sig_contrast': sigContrast,
        'sig_skew': sigSkew,
        'sig_shoulder': sigShoulder,
        'sig_toe': sigToe,
        'tone_equalizer_enabled': toneEqualizerEnabled,
        'te_blacks': teBlacks,
        'te_shadows': teShadows,
        'te_midtones': teMidtones,
        'te_highlights': teHighlights,
        'te_whites': teWhites,
        'highlight_enabled': highlightEnabled,
        'hl_recovery': hlRecovery,
        'hl_compress': hlCompress,
        'wb_enabled': wbEnabled,
        'wb_temperature': wbTemperature,
        'wb_tint': wbTint,
        'wb_as_shot_temp': wbAsShotTemp,
        'wb_as_shot_tint': wbAsShotTint,
        'color_zones_enabled': colorZonesEnabled,
        'sat_global': satGlobal,
        'sat_vibrance': satVibrance,
        'color_equalizer_enabled': colorEqualizerEnabled,
        'ceq_hue': List<double>.from(ceqHue),
        'ceq_sat': List<double>.from(ceqSat),
        'ceq_bri': List<double>.from(ceqBri),
        'color_balance_enabled': colorBalanceEnabled,
        'cb_shadows_r': cbShadowsR,
        'cb_midtones_g': cbMidtonesG,
        'cb_midtones_b': cbMidtonesB,
        'cb_highlights_r': cbHighlightsR,
        'color_grading_enabled': colorGradingEnabled,
        'cg_midtones_hue': cgMidtonesHue,
        'cg_midtones_sat': cgMidtonesSat,
        'cg_midtones_lum': cgMidtonesLum,
        'cg_shadows_hue': cgShadowsHue,
        'cg_shadows_sat': cgShadowsSat,
        'cg_shadows_lum': cgShadowsLum,
        'cg_highlights_hue': cgHighlightsHue,
        'cg_highlights_sat': cgHighlightsSat,
        'cg_highlights_lum': cgHighlightsLum,
        'cg_global_hue': cgGlobalHue,
        'cg_global_sat': cgGlobalSat,
        'cg_global_lum': cgGlobalLum,
        'cg_blending': cgBlending,
        'cg_balance': cgBalance,
        'calibration_enabled': calibrationEnabled,
        'calib_version': calibVersion,
        'calib_shadows_tint': calibShadowsTint,
        'calib_red_hue': calibRedHue,
        'calib_red_sat': calibRedSat,
        'calib_green_hue': calibGreenHue,
        'calib_green_sat': calibGreenSat,
        'calib_blue_hue': calibBlueHue,
        'calib_blue_sat': calibBlueSat,
        'lens_correction_enabled': lensCorrectionEnabled,
        'lens_profile_make': lensProfileMake,
        'lens_profile_model': lensProfileModel,
        'lens_distortion_scale': lensDistortionScale,
        'lens_vignette_scale': lensVignetteScale,
        'lens_tca_enabled': lensTcaEnabled,
        'lens_manual_distortion': lensManualDistortion,
        'lens_manual_vignette': lensManualVignette,
        'lens_manual_tca_r': lensManualTcaR,
        'lens_manual_tca_b': lensManualTcaB,
        'sharpen_enabled': sharpenEnabled,
        'sh_amount': shAmount,
        'local_contrast_enabled': localContrastEnabled,
        'lc_detail': lcDetail,
        'lc_clarity': lcClarity,
        'denoise_enabled': denoiseEnabled,
        'dn_strength': dnStrength,
        'dn_color': dnColor,
        'dn_detail': dnDetail,
        'blur_enabled': blurEnabled,
        'blur_radius': blurRadius,
        'grain_enabled': grainEnabled,
        'gr_amount': grAmount,
        'gr_size': grSize,
        'gr_roughness': grRoughness,
        'vignette_enabled': vignetteEnabled,
        'vg_amount': vgAmount,
        'vg_midpoint': vgMidpoint,
        'vg_feather': vgFeather,
        'vg_roundness': vgRoundness,
        'vg_highlights': vgHighlights,
        'dehaze_enabled': dehazeEnabled,
        'dh_strength': dhStrength,
        'defringe_enabled': defringeEnabled,
        'df_strength': dfStrength,
        'df_threshold': dfThreshold,
        'spot_enabled': spotEnabled,
        'spots': [for (final s in spots) s.toMap()],
        'red_eye_enabled': redEyeEnabled,
        'red_eyes': [for (final re in redEyes) re.toMap()],
        'liquify_enabled': liquifyEnabled,
        'liquify_tool': liquifyTool.name,
        'liquify_brush_size': liquifyBrushSize,
        'liquify_brush_pressure': liquifyBrushPressure,
        'liquify_show_guide': liquifyShowGuide,
        'liquify_face_detected': liquifyFaceDetected,
        'liquify_landmarks': liquifyLandmarks.toMap(),
        'liquify_face_params': liquifyFaceParams.toMap(),
        'liquify_dx': liquifyGrid.toDxList(),
        'liquify_dy': liquifyGrid.toDyList(),
        'split_view_enabled': splitViewEnabled,
        'split_position': splitPosition,
      };

  factory PipelineParams.fromMap(Map<String, dynamic> m) =>
      PipelineParams()..applyMap(m);

  /// 맵에 존재하는 키만 덮어씁니다 (원본 `from_dict`와 동일한 부분 적용 동작).
  void applyMap(Map m) {
    if (m.containsKey('rotate_90')) rotate90 = _d(m['rotate_90'], 0).toInt();
    if (m.containsKey('flip_h')) flipH = _b(m['flip_h'], flipH);
    if (m.containsKey('flip_v')) flipV = _b(m['flip_v'], flipV);
    if (m.containsKey('angle')) angle = _d(m['angle'], angle);
    if (m.containsKey('crop_enabled')) cropEnabled = _b(m['crop_enabled'], cropEnabled);
    if (m['crop_rect'] is List && (m['crop_rect'] as List).length == 4) {
      cropRect = [for (final e in m['crop_rect'] as List) _d(e, 0.0)];
    }
    if (m.containsKey('tone_curve_enabled')) {
      toneCurveEnabled = _b(m['tone_curve_enabled'], toneCurveEnabled);
    }
    if (m['tone_curve_points'] is Map) {
      final src = m['tone_curve_points'] as Map;
      final next = _identityCurves();
      for (final k in kCurveKeys) {
        final v = src[k];
        if (v is List && v.length >= 2) {
          next[k] = [
            for (final pt in v)
              if (pt is List && pt.length >= 2) [_d(pt[0], 0.0), _d(pt[1], 0.0)]
          ];
          if (next[k]!.length < 2) {
            next[k] = [
              [0.0, 0.0],
              [1.0, 1.0]
            ];
          }
        }
      }
      toneCurvePoints = next;
    }
    if (m.containsKey('exposure_enabled')) exposureEnabled = _b(m['exposure_enabled'], exposureEnabled);
    if (m.containsKey('exp_ev')) expEv = _d(m['exp_ev'], expEv);
    if (m.containsKey('exp_black_level')) expBlackLevel = _d(m['exp_black_level'], expBlackLevel);
    if (m.containsKey('exp_contrast')) expContrast = _d(m['exp_contrast'], expContrast);
    if (m.containsKey('sigmoid_enabled')) sigmoidEnabled = _b(m['sigmoid_enabled'], sigmoidEnabled);
    if (m.containsKey('sig_contrast')) sigContrast = _d(m['sig_contrast'], sigContrast);
    if (m.containsKey('sig_skew')) sigSkew = _d(m['sig_skew'], sigSkew);
    if (m.containsKey('sig_shoulder')) sigShoulder = _d(m['sig_shoulder'], sigShoulder);
    if (m.containsKey('sig_toe')) sigToe = _d(m['sig_toe'], sigToe);
    if (m.containsKey('tone_equalizer_enabled')) {
      toneEqualizerEnabled = _b(m['tone_equalizer_enabled'], toneEqualizerEnabled);
    }
    if (m.containsKey('te_blacks')) teBlacks = _d(m['te_blacks'], teBlacks);
    if (m.containsKey('te_shadows')) teShadows = _d(m['te_shadows'], teShadows);
    if (m.containsKey('te_midtones')) teMidtones = _d(m['te_midtones'], teMidtones);
    if (m.containsKey('te_highlights')) teHighlights = _d(m['te_highlights'], teHighlights);
    if (m.containsKey('te_whites')) teWhites = _d(m['te_whites'], teWhites);
    if (m.containsKey('highlight_enabled')) highlightEnabled = _b(m['highlight_enabled'], highlightEnabled);
    if (m.containsKey('hl_recovery')) hlRecovery = _d(m['hl_recovery'], hlRecovery);
    if (m.containsKey('hl_compress')) hlCompress = _d(m['hl_compress'], hlCompress);
    if (m.containsKey('wb_enabled')) wbEnabled = _b(m['wb_enabled'], wbEnabled);
    if (m.containsKey('wb_temperature')) wbTemperature = _d(m['wb_temperature'], wbTemperature);
    if (m.containsKey('wb_tint')) wbTint = _d(m['wb_tint'], wbTint);
    if (m.containsKey('wb_as_shot_temp')) wbAsShotTemp = _d(m['wb_as_shot_temp'], wbAsShotTemp);
    if (m.containsKey('wb_as_shot_tint')) wbAsShotTint = _d(m['wb_as_shot_tint'], wbAsShotTint);
    if (m.containsKey('color_zones_enabled')) colorZonesEnabled = _b(m['color_zones_enabled'], colorZonesEnabled);
    if (m.containsKey('sat_global')) satGlobal = _d(m['sat_global'], satGlobal);
    if (m.containsKey('sat_vibrance')) satVibrance = _d(m['sat_vibrance'], satVibrance);
    if (m.containsKey('color_equalizer_enabled')) {
      colorEqualizerEnabled = _b(m['color_equalizer_enabled'], colorEqualizerEnabled);
    }
    if (m.containsKey('ceq_hue')) ceqHue = _list8(m['ceq_hue']);
    if (m.containsKey('ceq_sat')) ceqSat = _list8(m['ceq_sat']);
    if (m.containsKey('ceq_bri')) ceqBri = _list8(m['ceq_bri']);
    if (m.containsKey('color_balance_enabled')) {
      colorBalanceEnabled = _b(m['color_balance_enabled'], colorBalanceEnabled);
    }
    if (m.containsKey('cb_shadows_r')) cbShadowsR = _d(m['cb_shadows_r'], cbShadowsR);
    if (m.containsKey('cb_midtones_g')) cbMidtonesG = _d(m['cb_midtones_g'], cbMidtonesG);
    if (m.containsKey('cb_midtones_b')) cbMidtonesB = _d(m['cb_midtones_b'], cbMidtonesB);
    if (m.containsKey('cb_highlights_r')) cbHighlightsR = _d(m['cb_highlights_r'], cbHighlightsR);
    if (m.containsKey('color_grading_enabled')) {
      colorGradingEnabled = _b(m['color_grading_enabled'], colorGradingEnabled);
    }
    if (m.containsKey('cg_midtones_hue')) cgMidtonesHue = _d(m['cg_midtones_hue'], cgMidtonesHue);
    if (m.containsKey('cg_midtones_sat')) cgMidtonesSat = _d(m['cg_midtones_sat'], cgMidtonesSat);
    if (m.containsKey('cg_midtones_lum')) cgMidtonesLum = _d(m['cg_midtones_lum'], cgMidtonesLum);
    if (m.containsKey('cg_shadows_hue')) cgShadowsHue = _d(m['cg_shadows_hue'], cgShadowsHue);
    if (m.containsKey('cg_shadows_sat')) cgShadowsSat = _d(m['cg_shadows_sat'], cgShadowsSat);
    if (m.containsKey('cg_shadows_lum')) cgShadowsLum = _d(m['cg_shadows_lum'], cgShadowsLum);
    if (m.containsKey('cg_highlights_hue')) cgHighlightsHue = _d(m['cg_highlights_hue'], cgHighlightsHue);
    if (m.containsKey('cg_highlights_sat')) cgHighlightsSat = _d(m['cg_highlights_sat'], cgHighlightsSat);
    if (m.containsKey('cg_highlights_lum')) cgHighlightsLum = _d(m['cg_highlights_lum'], cgHighlightsLum);
    if (m.containsKey('cg_global_hue')) cgGlobalHue = _d(m['cg_global_hue'], cgGlobalHue);
    if (m.containsKey('cg_global_sat')) cgGlobalSat = _d(m['cg_global_sat'], cgGlobalSat);
    if (m.containsKey('cg_global_lum')) cgGlobalLum = _d(m['cg_global_lum'], cgGlobalLum);
    if (m.containsKey('cg_blending')) cgBlending = _d(m['cg_blending'], cgBlending);
    if (m.containsKey('cg_balance')) cgBalance = _d(m['cg_balance'], cgBalance);

    if (m.containsKey('calibration_enabled')) {
      calibrationEnabled = _b(m['calibration_enabled'], calibrationEnabled);
    }
    if (m.containsKey('calib_version')) calibVersion = m['calib_version']?.toString() ?? calibVersion;
    if (m.containsKey('calib_shadows_tint')) calibShadowsTint = _d(m['calib_shadows_tint'], calibShadowsTint);
    if (m.containsKey('calib_red_hue')) calibRedHue = _d(m['calib_red_hue'], calibRedHue);
    if (m.containsKey('calib_red_sat')) calibRedSat = _d(m['calib_red_sat'], calibRedSat);
    if (m.containsKey('calib_green_hue')) calibGreenHue = _d(m['calib_green_hue'], calibGreenHue);
    if (m.containsKey('calib_green_sat')) calibGreenSat = _d(m['calib_green_sat'], calibGreenSat);
    if (m.containsKey('calib_blue_hue')) calibBlueHue = _d(m['calib_blue_hue'], calibBlueHue);
    if (m.containsKey('calib_blue_sat')) calibBlueSat = _d(m['calib_blue_sat'], calibBlueSat);

    if (m.containsKey('lens_correction_enabled')) {
      lensCorrectionEnabled = _b(m['lens_correction_enabled'], lensCorrectionEnabled);
    }
    if (m.containsKey('lens_profile_make')) lensProfileMake = m['lens_profile_make']?.toString() ?? lensProfileMake;
    if (m.containsKey('lens_profile_model')) lensProfileModel = m['lens_profile_model']?.toString() ?? lensProfileModel;
    if (m.containsKey('lens_distortion_scale')) lensDistortionScale = _d(m['lens_distortion_scale'], lensDistortionScale);
    if (m.containsKey('lens_vignette_scale')) lensVignetteScale = _d(m['lens_vignette_scale'], lensVignetteScale);
    if (m.containsKey('lens_tca_enabled')) lensTcaEnabled = _b(m['lens_tca_enabled'], lensTcaEnabled);
    if (m.containsKey('lens_manual_distortion')) lensManualDistortion = _d(m['lens_manual_distortion'], lensManualDistortion);
    if (m.containsKey('lens_manual_vignette')) lensManualVignette = _d(m['lens_manual_vignette'], lensManualVignette);
    if (m.containsKey('lens_manual_tca_r')) lensManualTcaR = _d(m['lens_manual_tca_r'], lensManualTcaR);
    if (m.containsKey('lens_manual_tca_b')) lensManualTcaB = _d(m['lens_manual_tca_b'], lensManualTcaB);
    if (m.containsKey('sharpen_enabled')) sharpenEnabled = _b(m['sharpen_enabled'], sharpenEnabled);
    if (m.containsKey('sh_amount')) shAmount = _d(m['sh_amount'], shAmount);
    if (m.containsKey('local_contrast_enabled')) {
      localContrastEnabled = _b(m['local_contrast_enabled'], localContrastEnabled);
    }
    if (m.containsKey('lc_detail')) lcDetail = _d(m['lc_detail'], lcDetail);
    if (m.containsKey('lc_clarity')) lcClarity = _d(m['lc_clarity'], lcClarity);
    if (m.containsKey('denoise_enabled')) denoiseEnabled = _b(m['denoise_enabled'], denoiseEnabled);
    if (m.containsKey('dn_strength')) dnStrength = _d(m['dn_strength'], dnStrength);
    if (m.containsKey('dn_color')) dnColor = _d(m['dn_color'], dnColor);
    if (m.containsKey('dn_detail')) dnDetail = _d(m['dn_detail'], dnDetail);
    if (m.containsKey('blur_enabled')) blurEnabled = _b(m['blur_enabled'], blurEnabled);
    if (m.containsKey('blur_radius')) blurRadius = _d(m['blur_radius'], blurRadius);
    if (m.containsKey('grain_enabled')) grainEnabled = _b(m['grain_enabled'], grainEnabled);
    if (m.containsKey('gr_amount')) grAmount = _d(m['gr_amount'], grAmount);
    if (m.containsKey('gr_size')) grSize = _d(m['gr_size'], grSize);
    if (m.containsKey('gr_roughness')) grRoughness = _d(m['gr_roughness'], grRoughness);
    if (m.containsKey('vignette_enabled')) vignetteEnabled = _b(m['vignette_enabled'], vignetteEnabled);
    if (m.containsKey('vg_amount')) vgAmount = _d(m['vg_amount'], vgAmount);
    if (m.containsKey('vg_midpoint')) vgMidpoint = _d(m['vg_midpoint'], vgMidpoint);
    if (m.containsKey('vg_feather')) vgFeather = _d(m['vg_feather'], vgFeather);
    if (m.containsKey('vg_roundness')) vgRoundness = _d(m['vg_roundness'], vgRoundness);
    if (m.containsKey('vg_highlights')) vgHighlights = _d(m['vg_highlights'], vgHighlights);
    if (m.containsKey('dehaze_enabled')) dehazeEnabled = _b(m['dehaze_enabled'], dehazeEnabled);
    if (m.containsKey('dh_strength')) dhStrength = _d(m['dh_strength'], dhStrength);
    if (m.containsKey('defringe_enabled')) defringeEnabled = _b(m['defringe_enabled'], defringeEnabled);
    if (m.containsKey('df_strength')) dfStrength = _d(m['df_strength'], dfStrength);
    if (m.containsKey('df_threshold')) dfThreshold = _d(m['df_threshold'], dfThreshold);
    if (m.containsKey('spot_enabled')) spotEnabled = _b(m['spot_enabled'], spotEnabled);
    if (m['spots'] is List) {
      spots = [
        for (final s in m['spots'] as List)
          if (s is Map) Spot.fromMap(s)
      ];
    }
    if (m.containsKey('red_eye_enabled')) {
      redEyeEnabled = _b(m['red_eye_enabled'], redEyeEnabled);
    }
    if (m['red_eyes'] is List) {
      redEyes = [
        for (final re in m['red_eyes'] as List)
          if (re is Map) RedEyeSpot.fromMap(re)
      ];
    }
    if (m.containsKey('liquify_enabled')) {
      liquifyEnabled = _b(m['liquify_enabled'], liquifyEnabled);
    }
    if (m.containsKey('liquify_tool') && m['liquify_tool'] is String) {
      try {
        liquifyTool = LiquifyToolType.values.byName(m['liquify_tool']);
      } catch (_) {}
    }
    if (m.containsKey('liquify_brush_size')) {
      liquifyBrushSize = _d(m['liquify_brush_size'], liquifyBrushSize);
    }
    if (m.containsKey('liquify_brush_pressure')) {
      liquifyBrushPressure = _d(m['liquify_brush_pressure'], liquifyBrushPressure);
    }
    if (m.containsKey('liquify_show_guide')) {
      liquifyShowGuide = _b(m['liquify_show_guide'], liquifyShowGuide);
    }
    if (m.containsKey('liquify_face_detected')) {
      liquifyFaceDetected = _b(m['liquify_face_detected'], liquifyFaceDetected);
    }
    if (m['liquify_landmarks'] is Map) {
      liquifyLandmarks = FaceLandmarks.fromMap(m['liquify_landmarks']);
    }
    if (m['liquify_face_params'] is Map) {
      liquifyFaceParams = FaceAwareParams.fromMap(m['liquify_face_params']);
    }
    if (m['liquify_dx'] is List && m['liquify_dy'] is List) {
      liquifyGrid = LiquifyDisplacementGrid.fromLists(m['liquify_dx'], m['liquify_dy']);
    }
    if (m.containsKey('split_view_enabled')) splitViewEnabled = _b(m['split_view_enabled'], splitViewEnabled);
    if (m.containsKey('split_position')) splitPosition = _d(m['split_position'], splitPosition);
  }

  /// 값 비교용(Undo 변경 감지) 문자열
  String fingerprint() => jsonEncode(toMap());
}
