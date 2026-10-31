import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../models/pipeline_params.dart';

/// 실시간 히스토그램 데이터
class HistogramData {
  final List<int> rBins;
  final List<int> gBins;
  final List<int> bBins;
  final List<int> lumaBins;
  final int maxBinValue;

  HistogramData({
    required this.rBins,
    required this.gBins,
    required this.bBins,
    required this.lumaBins,
    required this.maxBinValue,
  });

  factory HistogramData.empty() {
    return HistogramData(
      rBins: List.filled(256, 0),
      gBins: List.filled(256, 0),
      bBins: List.filled(256, 0),
      lumaBins: List.filled(256, 0),
      maxBinValue: 1,
    );
  }
}

/// SemiDarktable 32-bit Float 정밀 연산 엔진 (100% 포팅)
class PipelineEngine {
  /// 켈빈(Kelvin) 색온도를 RGB 게인으로 변환 (SemiDarktable 정밀 알고리즘)
  static List<double> kelvinToRgbGain(double kelvin) {
    final k = kelvin / 100.0;
    double r, g, b;

    if (k <= 66) {
      r = 255.0;
      g = 99.4708025861 * math.log(math.max(1.0, k)) - 161.1195681661;
    } else {
      r = 329.698727446 * math.pow(k - 60.0, -0.1332047592);
      g = 288.1221695283 * math.pow(k - 60.0, -0.0755148492);
    }

    if (k >= 66) {
      b = 255.0;
    } else if (k <= 19) {
      b = 0.0;
    } else {
      b = 138.5177312231 * math.log(math.max(1.0, k - 10.0)) - 305.0447927307;
    }

    r = r.clamp(0.0, 255.0) / 255.0;
    g = g.clamp(0.0, 255.0) / 255.0;
    b = b.clamp(0.0, 255.0) / 255.0;

    final gainR = 1.0 / math.max(0.01, r);
    final gainG = 1.0 / math.max(0.01, g);
    final gainB = 1.0 / math.max(0.01, b);
    final maxG = math.max(gainR, math.max(gainG, gainB));

    return [gainR / maxG, gainG / maxG, gainB / maxG];
  }

  /// 전체 32-bit 파이프라인 수행
  static ProcessResult process({
    required img.Image sourceImage,
    required PipelineParams params,
  }) {
    final width = sourceImage.width;
    final height = sourceImage.height;

    final rBins = List<int>.filled(256, 0);
    final gBins = List<int>.filled(256, 0);
    final bBins = List<int>.filled(256, 0);
    final lumaBins = List<int>.filled(256, 0);
    int maxBin = 1;

    // 1. 노출 및 명암 계수
    final expScale = math.pow(2.0, params.expEv).toDouble();
    final blackLevel = params.blackLevel;
    final contrast = params.contrast;
    final cFactor = (contrast >= 0) ? (1.0 + contrast * 1.5) : (1.0 + contrast * 0.8);

    // 2. 화이트 밸런스 (As-shot 기준 상대 게인)
    final targetGains = kelvinToRgbGain(params.wbTemperature);
    final baseGains = kelvinToRgbGain(params.wbAsShotTemp);
    final wbGainR = (targetGains[0] / math.max(0.01, baseGains[0]));
    final wbGainG = (targetGains[1] / math.max(0.01, baseGains[1])) * (1.0 - params.wbTint * 0.4);
    final wbGainB = (targetGains[2] / math.max(0.01, baseGains[2]));

    // 3. 채도 & 생동감
    final satScale = math.max(0.0, 1.0 + params.satGlobal);
    final vibrance = params.satVibrance;

    // 4. 시그모이드 파라미터
    final useSigmoid = params.sigmoidEnabled;
    final sigK = params.sigContrast * 4.0;
    final sigX0 = 0.5 + (params.sigSkew * 0.25);

    // 5. 5밴드 톤 이퀄라이저 계수
    final teBlacks = params.teBlacks;
    final teShadows = params.teShadows;
    final teMidtones = params.teMidtones;
    final teHighlights = params.teHighlights;
    final teWhites = params.teWhites;

    // 6. 비네팅 계수
    final useVignette = params.vignetteEnabled && params.vgAmount > 0.001;
    final vgAmount = params.vgAmount;
    final halfW = width * 0.5;
    final halfH = height * 0.5;
    final maxDist = math.sqrt(halfW * halfW + halfH * halfH);

    final img.Image output = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = sourceImage.getPixel(x, y);

        // 정규화 32비트 Float 선형 입력 (0.0 ~ 1.0)
        double r = pixel.rNormalized.toDouble();
        double g = pixel.gNormalized.toDouble();
        double b = pixel.bNormalized.toDouble();

        // 1. 화이트 밸런스 (As-Shot 연동 켈빈 & 틴트)
        if (params.wbEnabled) {
          r *= wbGainR;
          g *= wbGainG;
          b *= wbGainB;
        }

        // 2. 기본 노출 및 블랙 레벨
        if (params.exposureEnabled) {
          r = (r - blackLevel) * expScale;
          g = (g - blackLevel) * expScale;
          b = (b - blackLevel) * expScale;

          if (contrast != 0.0) {
            r = ((r - 0.18) * cFactor) + 0.18;
            g = ((g - 0.18) * cFactor) + 0.18;
            b = ((b - 0.18) * cFactor) + 0.18;
          }
        }

        // 3. 5밴드 톤 이퀄라이저 (Blacks, Shadows, Midtones, Highlights, Whites)
        if (params.toneEqualizerEnabled) {
          final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          double toneDelta = 0.0;

          if (luma < 0.15) {
            toneDelta += teBlacks * 0.25 * (1.0 - luma / 0.15);
          }
          if (luma >= 0.05 && luma < 0.4) {
            final w = 1.0 - ((luma - 0.2).abs() / 0.2);
            if (w > 0) toneDelta += teShadows * 0.3 * w;
          }
          if (luma >= 0.25 && luma < 0.75) {
            final w = 1.0 - ((luma - 0.5).abs() / 0.25);
            if (w > 0) toneDelta += teMidtones * 0.35 * w;
          }
          if (luma >= 0.6 && luma < 0.95) {
            final w = 1.0 - ((luma - 0.75).abs() / 0.2);
            if (w > 0) toneDelta += teHighlights * 0.3 * w;
          }
          if (luma >= 0.85) {
            toneDelta += teWhites * 0.25 * ((luma - 0.85) / 0.15);
          }

          r += toneDelta;
          g += toneDelta;
          b += toneDelta;
        }

        // 4. 하이라이트 복원 및 소프트 압축
        if (params.highlightEnabled && params.hlRecovery > 0.01) {
          final maxC = math.max(r, math.max(g, b));
          if (maxC > 0.8) {
            final compress = (maxC - 0.8) * params.hlRecovery * 0.5;
            r -= compress;
            g -= compress;
            b -= compress;
          }
        }

        r = math.max(0.0, r);
        g = math.max(0.0, g);
        b = math.max(0.0, b);

        // 5. 시그모이드 톤 매핑 (Sigmoid Tone Mapping)
        if (useSigmoid) {
          r = 1.0 / (1.0 + math.exp(-sigK * (r - sigX0)));
          g = 1.0 / (1.0 + math.exp(-sigK * (g - sigX0)));
          b = 1.0 / (1.0 + math.exp(-sigK * (b - sigX0)));
        }

        // 6. 채도(Saturation) 및 생동감(Vibrance)
        if (params.colorZonesEnabled && (satScale != 1.0 || vibrance != 0.0)) {
          final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final maxC = math.max(r, math.max(g, b));
          final minC = math.min(r, math.min(g, b));
          final currentSat = (maxC > 0.0) ? (maxC - minC) / maxC : 0.0;

          final vBoost = vibrance * (1.0 - currentSat);
          final finalSat = math.max(0.0, satScale + vBoost);

          r = luma + (r - luma) * finalSat;
          g = luma + (g - luma) * finalSat;
          b = luma + (b - luma) * finalSat;
        }

        // 7. 디헤이즈 (Dehaze - 대비 및 채도 결합 안개 제거)
        if (params.dehazeEnabled && params.dhStrength != 0.0) {
          final dh = params.dhStrength * 0.2;
          r = (r - dh).clamp(0.0, 1.0);
          g = (g - dh).clamp(0.0, 1.0);
          b = (b - dh).clamp(0.0, 1.0);
        }

        // 8. 비네팅 (Vignette)
        if (useVignette) {
          final dx = x - halfW;
          final dy = y - halfH;
          final dist = math.sqrt(dx * dx + dy * dy) / maxDist;
          final vigFactor = (1.0 - math.pow(dist, 2.0) * vgAmount).clamp(0.0, 1.0);
          r *= vigFactor;
          g *= vigFactor;
          b *= vigFactor;
        }

        // 최종 0.0 ~ 1.0 클리핑
        final outR = r.clamp(0.0, 1.0);
        final outG = g.clamp(0.0, 1.0);
        final outB = b.clamp(0.0, 1.0);

        final byteR = (outR * 255.0).round();
        final byteG = (outG * 255.0).round();
        final byteB = (outB * 255.0).round();
        final byteLuma = ((0.2126 * outR + 0.7152 * outG + 0.0722 * outB) * 255.0).round().clamp(0, 255);

        rBins[byteR]++;
        gBins[byteG]++;
        bBins[byteB]++;
        lumaBins[byteLuma]++;

        if (rBins[byteR] > maxBin) maxBin = rBins[byteR];
        if (gBins[byteG] > maxBin) maxBin = gBins[byteG];
        if (bBins[byteB] > maxBin) maxBin = bBins[byteB];

        output.setPixelRgba(x, y, byteR, byteG, byteB, pixel.a);
      }
    }

    final histogram = HistogramData(
      rBins: rBins,
      gBins: gBins,
      bBins: bBins,
      lumaBins: lumaBins,
      maxBinValue: maxBin,
    );

    return ProcessResult(image: output, histogram: histogram);
  }
}

class ProcessResult {
  final img.Image image;
  final HistogramData histogram;
  ProcessResult({required this.image, required this.histogram});
}
