/// PhotonRaw 파이프라인 파라미터 (SemiDarktable 100% 호환)
class PipelineParams {
  // 1. 기하학 / 방향
  int rotate90 = 0; // 0, 90, 180, 270
  bool flipH = false;
  bool flipV = false;

  // 2. 노출 (Exposure)
  bool exposureEnabled = true;
  double expEv = 0.0;          // -5.0 ~ 5.0 EV
  double blackLevel = 0.0;     // -0.2 ~ 0.2
  double contrast = 0.0;       // -1.0 ~ 1.0

  // 3. 화이트 밸런스 (다크테이블 Kelvin 및 Tint)
  bool wbEnabled = true;
  double wbTemperature = 6500.0; // 2000K ~ 12000K
  double wbTint = 0.0;           // -1.0 ~ 1.0 (Green <-> Magenta)
  double wbAsShotTemp = 6500.0;
  double wbAsShotTint = 0.0;

  // 4. 시그모이드 톤 매핑 (Sigmoid Tone Mapping)
  bool sigmoidEnabled = true;
  double sigContrast = 1.0;   // 0.5 ~ 2.5
  double sigSkew = 0.0;       // -1.0 ~ 1.0
  double sigShoulder = 0.0;   // -1.0 ~ 1.0
  double sigToe = 0.0;        // -1.0 ~ 1.0

  // 5. 5밴드 톤 이퀄라이저 (Tone Equalizer)
  bool toneEqualizerEnabled = true;
  double teBlacks = 0.0;      // -1.0 ~ 1.0
  double teShadows = 0.0;     // -1.0 ~ 1.0
  double teMidtones = 0.0;    // -1.0 ~ 1.0
  double teHighlights = 0.0;  // -1.0 ~ 1.0
  double teWhites = 0.0;      // -1.0 ~ 1.0

  // 6. 하이라이트 복원 (Highlight Recovery)
  bool highlightEnabled = true;
  double hlRecovery = 0.0;    // 0.0 ~ 1.0
  double hlCompress = 0.0;    // 0.0 ~ 1.0

  // 7. 채도 & 생동감 (Color Zones / Vibrance)
  bool colorZonesEnabled = true;
  double satGlobal = 0.0;     // -1.0 ~ 1.0
  double satVibrance = 0.0;   // -1.0 ~ 1.0

  // 8. 디헤이즈 & 비네팅 & 샤픈
  bool dehazeEnabled = false;
  double dhStrength = 0.0;    // -1.0 ~ 1.0 (안개 제거)

  bool vignetteEnabled = false;
  double vgAmount = 0.0;      // 0.0 ~ 1.0 (비네팅)

  bool sharpenEnabled = false;
  double shAmount = 0.0;      // 0.0 ~ 1.0 (선명도)

  bool grainEnabled = false;
  double grAmount = 0.0;      // 0.0 ~ 1.0 (필름 그레인)

  PipelineParams();

  PipelineParams clone() {
    final p = PipelineParams();
    p.rotate90 = rotate90;
    p.flipH = flipH;
    p.flipV = flipV;

    p.exposureEnabled = exposureEnabled;
    p.expEv = expEv;
    p.blackLevel = blackLevel;
    p.contrast = contrast;

    p.wbEnabled = wbEnabled;
    p.wbTemperature = wbTemperature;
    p.wbTint = wbTint;
    p.wbAsShotTemp = wbAsShotTemp;
    p.wbAsShotTint = wbAsShotTint;

    p.sigmoidEnabled = sigmoidEnabled;
    p.sigContrast = sigContrast;
    p.sigSkew = sigSkew;
    p.sigShoulder = sigShoulder;
    p.sigToe = sigToe;

    p.toneEqualizerEnabled = toneEqualizerEnabled;
    p.teBlacks = teBlacks;
    p.teShadows = teShadows;
    p.teMidtones = teMidtones;
    p.teHighlights = teHighlights;
    p.teWhites = teWhites;

    p.highlightEnabled = highlightEnabled;
    p.hlRecovery = hlRecovery;
    p.hlCompress = hlCompress;

    p.colorZonesEnabled = colorZonesEnabled;
    p.satGlobal = satGlobal;
    p.satVibrance = satVibrance;

    p.dehazeEnabled = dehazeEnabled;
    p.dhStrength = dhStrength;

    p.vignetteEnabled = vignetteEnabled;
    p.vgAmount = vgAmount;

    p.sharpenEnabled = sharpenEnabled;
    p.shAmount = shAmount;

    p.grainEnabled = grainEnabled;
    p.grAmount = grAmount;

    return p;
  }
}
