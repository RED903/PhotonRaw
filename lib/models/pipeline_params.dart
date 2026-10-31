/// PhotonRaw 파이프라인 파라미터 (SemiDarktable 100% 완전 호환)
class PipelineParams {
  // 1. 기하학 & 방향 (Orientation & Geometry)
  int rotate90 = 0; // 0, 90, 180, 270
  bool flipH = false;
  bool flipV = false;
  double angle = 0.0; // -45.0 ~ 45.0도
  bool cropEnabled = false;
  double cropL = 0.0;
  double cropT = 0.0;
  double cropR = 1.0;
  double cropB = 1.0;

  // 2. 노출 및 블랙 레벨 (Exposure)
  bool exposureEnabled = true;
  double expEv = 0.0;          // -5.0 ~ 5.0 EV
  double blackLevel = 0.0;     // -0.2 ~ 0.2
  double contrast = 0.0;       // -1.0 ~ 1.0

  // 3. 하이라이트 복원 (Highlight Recovery)
  bool highlightEnabled = true;
  double hlRecovery = 0.0;     // 0.0 ~ 1.0
  double hlCompress = 0.0;     // 0.0 ~ 1.0

  // 4. 5밴드 톤 이퀄라이저 (Tone Equalizer)
  bool toneEqualizerEnabled = true;
  double teBlacks = 0.0;       // -1.0 ~ 1.0
  double teShadows = 0.0;      // -1.0 ~ 1.0
  double teMidtones = 0.0;     // -1.0 ~ 1.0
  double teHighlights = 0.0;   // -1.0 ~ 1.0
  double teWhites = 0.0;       // -1.0 ~ 1.0

  // 5. 톤 커브 (Tone Curve - RGB, R, G, B 제어점)
  bool toneCurveEnabled = false;
  List<CurvePoint> curveRgb = [const CurvePoint(0.0, 0.0), const CurvePoint(1.0, 1.0)];
  List<CurvePoint> curveR = [const CurvePoint(0.0, 0.0), const CurvePoint(1.0, 1.0)];
  List<CurvePoint> curveG = [const CurvePoint(0.0, 0.0), const CurvePoint(1.0, 1.0)];
  List<CurvePoint> curveB = [const CurvePoint(0.0, 0.0), const CurvePoint(1.0, 1.0)];

  // 6. 시그모이드 톤 매핑 (Sigmoid Tone Mapping)
  bool sigmoidEnabled = true;
  double sigContrast = 1.0;    // 0.5 ~ 2.5
  double sigSkew = 0.0;        // -1.0 ~ 1.0
  double sigShoulder = 0.0;    // -1.0 ~ 1.0
  double sigToe = 0.0;         // -1.0 ~ 1.0

  // 7. 화이트 밸런스 (As-Shot 기준 켈빈 & 틴트)
  bool wbEnabled = true;
  double wbTemperature = 6500.0; // 2000K ~ 12000K
  double wbTint = 0.0;           // -1.0 ~ 1.0
  double wbAsShotTemp = 6500.0;
  double wbAsShotTint = 0.0;

  // 8. 채도 & 생동감 (Color Zones)
  bool colorZonesEnabled = true;
  double satGlobal = 0.0;      // -1.0 ~ 1.0
  double satVibrance = 0.0;    // -1.0 ~ 1.0

  // 9. 8밴드 컬러 이퀄라이저 (Color Equalizer - 8개 색상별 HSL)
  // 색상 순서: Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta
  bool colorEqualizerEnabled = false;
  List<double> ceqHue = List.filled(8, 0.0); // -1.0 ~ 1.0
  List<double> ceqSat = List.filled(8, 0.0); // -1.0 ~ 1.0
  List<double> ceqBri = List.filled(8, 0.0); // -1.0 ~ 1.0

  // 10. 컬러 밸런스 RGB (Color Balance RGB)
  bool colorBalanceEnabled = false;
  double cbShadowsR = 0.0;     // -1.0 ~ 1.0
  double cbMidtonesG = 0.0;    // -1.0 ~ 1.0
  double cbMidtonesB = 0.0;    // -1.0 ~ 1.0
  double cbHighlightsR = 0.0;  // -1.0 ~ 1.0

  // 11. 로컬 콘트라스트 & 샤픈 (Local Contrast & Sharpen)
  bool sharpenEnabled = false;
  double shAmount = 0.0;       // 0.0 ~ 1.0

  bool localContrastEnabled = false;
  double lcDetail = 0.0;       // 0.0 ~ 1.0
  double lcClarity = 0.0;      // 0.0 ~ 1.0

  // 12. 노이즈 제거 & 블러 (Denoise & Blur)
  bool denoiseEnabled = false;
  double dnStrength = 0.0;     // 0.0 ~ 1.0

  bool blurEnabled = false;
  double blurRadius = 0.0;     // 0.0 ~ 20.0

  // 13. 필름 그레인 & 비네팅 (Film Grain & Vignette)
  bool grainEnabled = false;
  double grAmount = 0.0;       // 0.0 ~ 1.0

  bool vignetteEnabled = false;
  double vgAmount = 0.0;       // 0.0 ~ 1.0

  // 14. 디헤이즈 & 디프린지 (Dehaze & Defringe)
  bool dehazeEnabled = false;
  double dhStrength = 0.0;     // -1.0 ~ 1.0 (안개 제거)

  bool defringeEnabled = false;
  double dfStrength = 0.0;     // 0.0 ~ 1.0 (색수차/퍼플 프린징 제거)

  PipelineParams();

  PipelineParams clone() {
    final p = PipelineParams();
    p.rotate90 = rotate90;
    p.flipH = flipH;
    p.flipV = flipV;
    p.angle = angle;
    p.cropEnabled = cropEnabled;
    p.cropL = cropL;
    p.cropT = cropT;
    p.cropR = cropR;
    p.cropB = cropB;

    p.exposureEnabled = exposureEnabled;
    p.expEv = expEv;
    p.blackLevel = blackLevel;
    p.contrast = contrast;

    p.highlightEnabled = highlightEnabled;
    p.hlRecovery = hlRecovery;
    p.hlCompress = hlCompress;

    p.toneEqualizerEnabled = toneEqualizerEnabled;
    p.teBlacks = teBlacks;
    p.teShadows = teShadows;
    p.teMidtones = teMidtones;
    p.teHighlights = teHighlights;
    p.teWhites = teWhites;

    p.toneCurveEnabled = toneCurveEnabled;
    p.curveRgb = List.from(curveRgb);
    p.curveR = List.from(curveR);
    p.curveG = List.from(curveG);
    p.curveB = List.from(curveB);

    p.sigmoidEnabled = sigmoidEnabled;
    p.sigContrast = sigContrast;
    p.sigSkew = sigSkew;
    p.sigShoulder = sigShoulder;
    p.sigToe = sigToe;

    p.wbEnabled = wbEnabled;
    p.wbTemperature = wbTemperature;
    p.wbTint = wbTint;
    p.wbAsShotTemp = wbAsShotTemp;
    p.wbAsShotTint = wbAsShotTint;

    p.colorZonesEnabled = colorZonesEnabled;
    p.satGlobal = satGlobal;
    p.satVibrance = satVibrance;

    p.colorEqualizerEnabled = colorEqualizerEnabled;
    p.ceqHue = List.from(ceqHue);
    p.ceqSat = List.from(ceqSat);
    p.ceqBri = List.from(ceqBri);

    p.colorBalanceEnabled = colorBalanceEnabled;
    p.cbShadowsR = cbShadowsR;
    p.cbMidtonesG = cbMidtonesG;
    p.cbMidtonesB = cbMidtonesB;
    p.cbHighlightsR = cbHighlightsR;

    p.sharpenEnabled = sharpenEnabled;
    p.shAmount = shAmount;

    p.localContrastEnabled = localContrastEnabled;
    p.lcDetail = lcDetail;
    p.lcClarity = lcClarity;

    p.denoiseEnabled = denoiseEnabled;
    p.dnStrength = dnStrength;

    p.blurEnabled = blurEnabled;
    p.blurRadius = blurRadius;

    p.grainEnabled = grainEnabled;
    p.grAmount = grAmount;

    p.vignetteEnabled = vignetteEnabled;
    p.vgAmount = vgAmount;

    p.dehazeEnabled = dehazeEnabled;
    p.dhStrength = dhStrength;

    p.defringeEnabled = defringeEnabled;
    p.dfStrength = dfStrength;

    return p;
  }
}

class CurvePoint {
  final double x;
  final double y;
  const CurvePoint(this.x, this.y);
}
