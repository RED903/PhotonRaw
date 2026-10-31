import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/pipeline_params.dart';

/// 히스토그램 데이터 모델
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

/// PhotonRaw 고성능 32-bit 부동소수점 이미지 프로세싱 파이프라인
class PipelineEngine {
  /// 원본 이미지(img.Image)에 PipelineParams 파라미터를 적용하여
  /// 가공된 결과물 이미지와 실시간 히스토그램 데이터를 반환합니다.
  static ProcessResult process({
    required img.Image sourceImage,
    required PipelineParams params,
  }) {
    final width = sourceImage.width;
    final height = sourceImage.height;

    // 히스토그램 빈 배열 초기화 (256단계)
    final rBins = List<int>.filled(256, 0);
    final gBins = List<int>.filled(256, 0);
    final bBins = List<int>.filled(256, 0);
    final lumaBins = List<int>.filled(256, 0);
    int maxBin = 1;

    // 노출 배율 계산: 2^EV
    final double expScale = math.pow(2.0, params.exposureEv).toDouble();
    final double blackLevel = params.blackLevel;
    final double contrast = params.contrast;

    // 화이트 밸런스 승수 (온도: 주황/파랑, 틴트: 녹색/마젠타)
    final double tempFactor = params.temperature / 100.0;
    final double tintFactor = params.tint / 100.0;
    final double rGain = 1.0 + tempFactor * 0.4;
    final double gGain = 1.0 - tintFactor * 0.3;
    final double bGain = 1.0 - tempFactor * 0.4;

    // 채도 / 생동감 승수
    final double satFactor = 1.0 + (params.saturation / 100.0);
    final double vibFactor = params.vibrance / 100.0;

    // 하이라이트 & 섀도우 조절량
    final double hlFactor = params.highlights / 100.0;
    final double shFactor = params.shadows / 100.0;

    // 시그모이드 톤 매핑 파라미터
    final bool useSigmoid = params.sigmoidEnabled;
    final double sigContrast = params.sigContrast;
    final double sigSkew = params.sigSkew;

    // 출력 이미지 버퍼 (RGBA)
    final img.Image output = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = sourceImage.getPixel(x, y);

        // 1. 선형 0.0 ~ 1.0 정규화 (32비트 Float 연산)
        double r = pixel.rNormalized.toDouble();
        double g = pixel.gNormalized.toDouble();
        double b = pixel.bNormalized.toDouble();

        // 2. 화이트 밸런스 / 틴트 적용
        if (params.whiteBalanceEnabled) {
          r *= rGain;
          g *= gGain;
          b *= bGain;
        }

        // 3. 노출 및 블랙 레벨
        if (params.exposureEnabled) {
          r = (r - blackLevel) * expScale;
          g = (g - blackLevel) * expScale;
          b = (b - blackLevel) * expScale;

          // 콘트라스트 (중간값 0.18 기준)
          if (contrast != 0.0) {
            final cFactor = (contrast > 0) ? (1.0 + contrast * 1.5) : (1.0 + contrast * 0.8);
            r = ((r - 0.18) * cFactor) + 0.18;
            g = ((g - 0.18) * cFactor) + 0.18;
            b = ((b - 0.18) * cFactor) + 0.18;
          }
        }

        // 4. 하이라이트 & 섀도우 복원
        if (params.toneDetailEnabled) {
          final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          if (shFactor != 0.0 && luma < 0.5) {
            final weight = (1.0 - (luma / 0.5));
            final boost = shFactor * 0.3 * weight;
            r += boost;
            g += boost;
            b += boost;
          }
          if (hlFactor != 0.0 && luma > 0.5) {
            final weight = ((luma - 0.5) / 0.5);
            final boost = hlFactor * 0.3 * weight;
            r += boost;
            g += boost;
            b += boost;
          }
        }

        // 음수 클리핑 방지
        r = math.max(0.0, r);
        g = math.max(0.0, g);
        b = math.max(0.0, b);

        // 5. 시그모이드(Sigmoid) 톤 매핑
        if (useSigmoid) {
          r = _applySigmoid(r, sigContrast, sigSkew);
          g = _applySigmoid(g, sigContrast, sigSkew);
          b = _applySigmoid(b, sigContrast, sigSkew);
        }

        // 6. 채도(Saturation) & 생동감(Vibrance)
        if (satFactor != 1.0 || vibFactor != 0.0) {
          final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final maxC = math.max(r, math.max(g, b));
          final minC = math.min(r, math.min(g, b));
          final currentSat = (maxC > 0) ? (maxC - minC) / maxC : 0.0;

          // Vibrance는 낮은 채도에 더 강하게 반응
          final vBoost = vibFactor * (1.0 - currentSat);
          final totalSat = math.max(0.0, satFactor + vBoost);

          r = luma + (r - luma) * totalSat;
          g = luma + (g - luma) * totalSat;
          b = luma + (b - luma) * totalSat;
        }

        // 7. 최종 0.0 ~ 1.0 클리핑
        final outR = r.clamp(0.0, 1.0);
        final outG = g.clamp(0.0, 1.0);
        final outB = b.clamp(0.0, 1.0);

        // 8. 8비트 정수 변환 및 히스토그램 카운팅
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

  /// 시그모이드 곡선 함수 (Darktable 스타일)
  static double _applySigmoid(double x, double contrast, double skew) {
    final x0 = 0.5 + (skew * 0.25);
    final k = contrast * 4.0;
    final val = 1.0 / (1.0 + math.exp(-k * (x - x0)));
    return val.clamp(0.0, 1.0);
  }
}

class ProcessResult {
  final img.Image image;
  final HistogramData histogram;
  ProcessResult({required this.image, required this.histogram});
}
