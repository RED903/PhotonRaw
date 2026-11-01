import 'dart:math' as math;
import 'dart:typed_data';

import '../models/pipeline_params.dart';
import 'curve_lut.dart';

/// 선형 RGB 32-bit float 이미지 (RGB 인터리브)
class FloatImage {
  final int width;
  final int height;
  final Float32List data;
  FloatImage(this.width, this.height, this.data);
}

/// 프록시 또는 풀 해상도 이미지 컨테이너
/// - 14/16-bit RAW 및 16-bit TIFF의 경우 [linearRgb]에 무손실 32-bit Float 선형 데이터가 그대로 보관되어 절대 8비트로 다운스케일되지 않음
/// - 일반 8-bit 이미지나 빠른 밝기 추정용으로 [rgb]도 함께 제공
class ProxyImage {
  final int width;
  final int height;
  final Uint8List rgb;
  final Float32List? linearRgb;
  ProxyImage(this.width, this.height, this.rgb, [this.linearRgb]);
}

// ───────────────────────── 색 변환 상수 / LUT ─────────────────────────

const List<double> _mToAces = [
  0.6131, 0.3395, 0.0474, //
  0.0701, 0.9164, 0.0135, //
  0.0206, 0.1096, 0.8698,
];
const List<double> _mFromAces = [
  1.7049, -0.6217, -0.0832, //
  -0.1301, 1.1408, -0.0107, //
  -0.0240, -0.1290, 1.1530,
];

final Float32List _srgbToLinearLut = () {
  final l = Float32List(256);
  for (var i = 0; i < 256; i++) {
    final c = i / 255.0;
    l[i] = c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }
  return l;
}();

const int _oetfN = 8192;
final Float32List _oetfLut = () {
  final l = Float32List(_oetfN + 2);
  for (var i = 0; i <= _oetfN + 1; i++) {
    final c = math.min(1.0, i / _oetfN);
    l[i] = c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
  }
  return l;
}();

const int _g22N = 4095;
final Float32List _linToGamma22Lut = () {
  final l = Float32List(_g22N + 1);
  for (var i = 0; i <= _g22N; i++) {
    l[i] = math.pow(i / _g22N, 1.0 / 2.2).toDouble();
  }
  return l;
}();

final Float32List _gamma22ToLinLut = () {
  final l = Float32List(_g22N + 1);
  for (var i = 0; i <= _g22N; i++) {
    l[i] = math.pow(i / _g22N, 2.2).toDouble();
  }
  return l;
}();

@pragma('vm:prefer-inline')
double _fastPowInv22(double x) {
  if (x <= 0.0) return 0.0;
  if (x >= 1.0) return 1.0;
  return _linToGamma22Lut[(x * _g22N + 0.5).toInt()];
}

@pragma('vm:prefer-inline')
double _fastPow22(double x) {
  if (x <= 0.0) return 0.0;
  if (x >= 1.0) return 1.0;
  return _gamma22ToLinLut[(x * _g22N + 0.5).toInt()];
}

/// IEC 61966-2-1 sRGB OETF (원본 셰이더와 동일)
double linearToSrgb(double c) {
  if (c <= 0.0) return 0.0;
  if (c >= 1.0) return 1.0;
  final f = c * _oetfN;
  final i = f.floor();
  final t = f - i;
  return _oetfLut[i] * (1.0 - t) + _oetfLut[i + 1] * t;
}

/// 입력 이미지를 32-bit 선형 Float로 변환
/// - 14/16-bit RAW 데이터([src.linearRgb]가 존재하는 경우)는 8비트 양자화를 절대 거치지 않고 순수 32-bit Float 버퍼 사본을 그대로 반환
FloatImage srgb8ToLinear(ProxyImage src) {
  if (src.linearRgb != null) {
    return FloatImage(
      src.width,
      src.height,
      Float32List.fromList(src.linearRgb!),
    );
  }
  final n = src.width * src.height * 3;
  final out = Float32List(n);
  final rgb = src.rgb;
  for (var i = 0; i < n; i++) {
    out[i] = _srgbToLinearLut[rgb[i]];
  }
  return FloatImage(src.width, src.height, out);
}

/// 선형 float → 16-bit sRGB (16-bit Master TIFF 무손실 내보내기용)
Uint16List toRgb16(FloatImage img) {
  final n = img.width * img.height * 3;
  final out = Uint16List(n);
  final d = img.data;
  for (var i = 0; i < n; i++) {
    out[i] = (linearToSrgb(d[i]) * 65535.0 + 0.5).floor().clamp(0, 65535);
  }
  return out;
}

/// 선형 float → RGBA8 (표시용)
Uint8List toRgba8(FloatImage img) {
  final n = img.width * img.height;
  final out = Uint8List(n * 4);
  final d = img.data;
  for (var i = 0; i < n; i++) {
    final o = i * 3;
    final q = i * 4;
    out[q] = (linearToSrgb(d[o]) * 255.0 + 0.5).floor();
    out[q + 1] = (linearToSrgb(d[o + 1]) * 255.0 + 0.5).floor();
    out[q + 2] = (linearToSrgb(d[o + 2]) * 255.0 + 0.5).floor();
    out[q + 3] = 255;
  }
  return out;
}

/// 선형 float → RGB8 (내보내기용)
Uint8List toRgb8(FloatImage img) {
  final n = img.width * img.height * 3;
  final out = Uint8List(n);
  final d = img.data;
  for (var i = 0; i < n; i++) {
    out[i] = (linearToSrgb(d[i]) * 255.0 + 0.5).floor();
  }
  return out;
}

// ───────────────────────── 화이트 밸런스 수학 ─────────────────────────

class ColorMath {
  static List<double> kelvinToRgbGain(double kelvin) {
    final k = kelvin / 100.0;
    double r;
    double g;
    double b;

    if (k <= 66) {
      r = 255.0;
    } else {
      r = 329.698727446 * math.pow(k - 60.0, -0.1332047592).toDouble();
    }

    if (k <= 66) {
      g = 99.4708025861 * math.log(math.max(1.0, k)) - 161.1195681661;
    } else {
      g = 288.1221695283 * math.pow(k - 60.0, -0.0755148492).toDouble();
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

  /// As-Shot 기준 상대 게인 (target==as-shot 이면 정확히 (1,1,1), 0.0)
  static ({List<double> gain, double deltaTint}) relativeWbGain(
    double targetTemp,
    double targetTint,
    double asShotTemp,
    double asShotTint,
  ) {
    final gt = kelvinToRgbGain(targetTemp);
    final gb = kelvinToRgbGain(asShotTemp);
    final relR = gt[0] / math.max(0.01, gb[0]);
    final relG = gt[1] / math.max(0.01, gb[1]);
    final relB = gt[2] / math.max(0.01, gb[2]);
    final norm = relG > 0.01 ? relG : 1.0;
    return (gain: [relR / norm, 1.0, relB / norm], deltaTint: targetTint - asShotTint);
  }

  /// 스포이드 샘플(선형 RGB)을 중립으로 만드는 색온도/틴트 역산
  static ({int temp, double tint}) wbFromSample(
    double sr,
    double sg,
    double sb,
    double asShotTemp,
    double asShotTint,
  ) {
    final r = math.max(0.0001, sr);
    final g = math.max(0.0001, sg);
    final b = math.max(0.0001, sb);
    final targetRb = b / r;

    var bestTemp = asShotTemp.toInt();
    var minDiff = double.infinity;
    for (var t = 2000; t <= 12000; t += 50) {
      final rel = relativeWbGain(t.toDouble(), 0.0, asShotTemp, 0.0);
      if (rel.gain[2] > 0.001) {
        final cur = rel.gain[0] / rel.gain[2];
        final diff = (cur - targetRb).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestTemp = t;
        }
      }
    }

    final rbAvg = (r + b) * 0.5;
    final greenDiff = (g - rbAvg) / math.max(0.001, g);
    final deltaTint = (-greenDiff * 1.5).clamp(-1.0, 1.0).toDouble();
    final bestTint = ((asShotTint + deltaTint) * 100).round() / 100.0;
    return (temp: bestTemp, tint: bestTint.clamp(-1.0, 1.0).toDouble());
  }
}

// ───────────────────────── 기하학 ─────────────────────────

FloatImage applyGeometry(FloatImage src, PipelineParams p, {bool ignoreAngle = false}) {
  var img = src;
  if (p.rotate90 == 90 || p.rotate90 == 180 || p.rotate90 == 270) {
    img = _rotate90(img, p.rotate90);
  }
  if (p.flipH) img = _flipH(img);
  if (p.flipV) img = _flipV(img);
  if (p.cropEnabled) img = _crop(img, p.cropRect);
  if (!ignoreAngle && p.angle.abs() > 0.01) img = _rotateAndCrop(img, p.angle);
  return img;
}

FloatImage _rotate90(FloatImage s, int deg) {
  final w = s.width;
  final h = s.height;
  final src = s.data;
  if (deg == 180) {
    final out = Float32List(src.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final so = ((h - 1 - y) * w + (w - 1 - x)) * 3;
        final o = (y * w + x) * 3;
        out[o] = src[so];
        out[o + 1] = src[so + 1];
        out[o + 2] = src[so + 2];
      }
    }
    return FloatImage(w, h, out);
  }
  final nw = h;
  final nh = w;
  final out = Float32List(nw * nh * 3);
  for (var y = 0; y < nh; y++) {
    for (var x = 0; x < nw; x++) {
      final int sy;
      final int sx;
      if (deg == 90) {
        sy = h - 1 - x;
        sx = y;
      } else {
        sy = x;
        sx = w - 1 - y;
      }
      final so = (sy * w + sx) * 3;
      final o = (y * nw + x) * 3;
      out[o] = src[so];
      out[o + 1] = src[so + 1];
      out[o + 2] = src[so + 2];
    }
  }
  return FloatImage(nw, nh, out);
}

FloatImage _flipH(FloatImage s) {
  final w = s.width;
  final h = s.height;
  final out = Float32List(s.data.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final so = (y * w + (w - 1 - x)) * 3;
      final o = (y * w + x) * 3;
      out[o] = s.data[so];
      out[o + 1] = s.data[so + 1];
      out[o + 2] = s.data[so + 2];
    }
  }
  return FloatImage(w, h, out);
}

FloatImage _flipV(FloatImage s) {
  final w = s.width;
  final h = s.height;
  final out = Float32List(s.data.length);
  for (var y = 0; y < h; y++) {
    final so = (h - 1 - y) * w * 3;
    final o = y * w * 3;
    out.setRange(o, o + w * 3, s.data, so);
  }
  return FloatImage(w, h, out);
}

FloatImage _crop(FloatImage s, List<double> r) {
  final w = s.width;
  final h = s.height;
  if (w < 3 || h < 3) return s;
  final cx = r[0], cy = r[1], cw = r[2], ch = r[3];
  final x0 = math.max(0, math.min(w - 2, (cx * w).toInt()));
  final y0 = math.max(0, math.min(h - 2, (cy * h).toInt()));
  final x1 = math.max(x0 + 1, math.min(w, ((cx + cw) * w).toInt()));
  final y1 = math.max(y0 + 1, math.min(h, ((cy + ch) * h).toInt()));
  final nw = x1 - x0;
  final nh = y1 - y0;
  final out = Float32List(nw * nh * 3);
  for (var y = 0; y < nh; y++) {
    final so = ((y0 + y) * w + x0) * 3;
    out.setRange(y * nw * 3, (y + 1) * nw * 3, s.data, so);
  }
  return FloatImage(nw, nh, out);
}

/// 화면 기준 시계 방향으로 [angle]도 회전 후, 검은 모서리가 생기지 않도록 중앙 크롭
FloatImage _rotateAndCrop(FloatImage s, double angle) {
  final w = s.width;
  final h = s.height;
  final rad = angle * math.pi / 180.0;
  final cosA = math.cos(rad).abs();
  final sinA = math.sin(rad).abs();
  final aspect = w / math.max(1, h);
  final scale = math.min(1.0 / (cosA + sinA / aspect), 1.0 / (cosA + sinA * aspect));

  final cropW = math.max(1, (w * scale).toInt());
  final cropH = math.max(1, (h * scale).toInt());
  final left = (w - cropW) ~/ 2;
  final top = (h - cropH) ~/ 2;

  final c = math.cos(rad);
  final sn = math.sin(rad);
  final out = Float32List(cropW * cropH * 3);
  final src = s.data;

  for (var oy = 0; oy < cropH; oy++) {
    final py = oy + top + 0.5 - h / 2.0;
    for (var ox = 0; ox < cropW; ox++) {
      final px = ox + left + 0.5 - w / 2.0;
      // 시계 방향 회전의 역변환
      final sx = c * px + sn * py + w / 2.0 - 0.5;
      final sy = -sn * px + c * py + h / 2.0 - 0.5;

      var x0 = sx.floor();
      var y0 = sy.floor();
      final fx = sx - x0;
      final fy = sy - y0;
      var x1 = x0 + 1;
      var y1 = y0 + 1;
      x0 = x0.clamp(0, w - 1);
      x1 = x1.clamp(0, w - 1);
      y0 = y0.clamp(0, h - 1);
      y1 = y1.clamp(0, h - 1);

      final i00 = (y0 * w + x0) * 3;
      final i10 = (y0 * w + x1) * 3;
      final i01 = (y1 * w + x0) * 3;
      final i11 = (y1 * w + x1) * 3;
      final o = (oy * cropW + ox) * 3;
      for (var ch = 0; ch < 3; ch++) {
        final top2 = src[i00 + ch] * (1 - fx) + src[i10 + ch] * fx;
        final bot = src[i01 + ch] * (1 - fx) + src[i11 + ch] * fx;
        out[o + ch] = top2 * (1 - fy) + bot * fy;
      }
    }
  }
  return FloatImage(cropW, cropH, out);
}

// ───────────────────────── HSL 도우미 ─────────────────────────

double _fract(double v) => v - v.floorToDouble();

/// 셰이더 rgb2hsl 과 동일 (결과: out[0]=h, out[1]=s, out[2]=l)
void _rgb2hsl(double r, double g, double b, Float64List out) {
  final cMin = math.min(math.min(r, g), b);
  final cMax = math.max(math.max(r, g), b);
  final delta = cMax - cMin;
  var h = 0.0;
  var s = 0.0;
  final l = (cMax + cMin) * 0.5;
  if (delta > 0.00001) {
    if (l < 0.5) {
      s = delta / (cMax + cMin);
    } else {
      s = delta / (2.0 - cMax - cMin);
    }
    if (r >= cMax) {
      h = (g - b) / delta;
    } else if (g >= cMax) {
      h = 2.0 + (b - r) / delta;
    } else {
      h = 4.0 + (r - g) / delta;
    }
    h = _fract(h / 6.0);
  }
  out[0] = h;
  out[1] = s;
  out[2] = l;
}

double _hue2rgb(double p, double q, double t0) {
  var t = t0;
  if (t < 0.0) t += 1.0;
  if (t > 1.0) t -= 1.0;
  if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
  if (t < 0.5) return q;
  if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
  return p;
}

void _hsl2rgb(double h, double s, double l, Float64List out) {
  if (s <= 0.0001) {
    out[0] = l;
    out[1] = l;
    out[2] = l;
    return;
  }
  final q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
  final p = 2.0 * l - q;
  out[0] = _hue2rgb(p, q, h + 1.0 / 3.0);
  out[1] = _hue2rgb(p, q, h);
  out[2] = _hue2rgb(p, q, h - 1.0 / 3.0);
}

const List<double> kCeqCenters = [
  0.0,
  35.0 / 360.0,
  60.0 / 360.0,
  120.0 / 360.0,
  180.0 / 360.0,
  240.0 / 360.0,
  280.0 / 360.0,
  325.0 / 360.0,
];

// ───────────────────────── 메인 색 파이프라인 ─────────────────────────

double _lutAt(Float32List lut, double x) {
  final f = x.clamp(0.0, 1.0) * 255.0;
  var i = f.floor();
  if (i > 254) i = 254;
  final t = f - i;
  return lut[i] * (1.0 - t) + lut[i + 1] * t;
}

bool _any(List<double> v) {
  for (final e in v) {
    if (e != 0.0) return true;
  }
  return false;
}

/// 기하학이 적용된 선형 이미지에 모든 보정 모듈을 적용 (원본 GLSL 셰이더 순서/수식 그대로)
FloatImage applyPipeline(FloatImage geo, PipelineParams p) {
  final w = geo.width;
  final h = geo.height;
  final buf = Float32List.fromList(geo.data);

  if (p.spotEnabled && p.spots.isNotEmpty) {
    _applySpots(buf, w, h, p.spots);
  }

  _colorStage(buf, w, h, p);

  if (p.redEyeEnabled && p.redEyes.isNotEmpty) {
    _applyRedEyes(buf, w, h, p.redEyes);
  }

  final detailed = _detailsStage(buf, w, h, p);
  return FloatImage(w, h, detailed);
}

void _colorStage(Float32List buf, int w, int h, PipelineParams p) {
  // ── 모듈별 활성 여부 (기본값이면 건너뛰어 항등 유지) ──
  final wbRel = ColorMath.relativeWbGain(p.wbTemperature, p.wbTint, p.wbAsShotTemp, p.wbAsShotTint);
  final wbActive = p.wbEnabled && (p.wbTemperature != p.wbAsShotTemp || p.wbTint != p.wbAsShotTint);
  final hlActive = p.highlightEnabled && (p.hlRecovery > 0 || p.hlCompress > 0);
  final expActive = p.exposureEnabled && (p.expEv != 0 || p.expBlackLevel != 0 || p.expContrast != 0);
  final teActive = p.toneEqualizerEnabled &&
      (p.teBlacks != 0 || p.teShadows != 0 || p.teMidtones != 0 || p.teHighlights != 0 || p.teWhites != 0);
  final sigActive = p.sigmoidEnabled &&
      ((p.sigContrast - 1.0).abs() > 0.001 ||
          p.sigSkew.abs() > 0.001 ||
          p.sigShoulder.abs() > 0.001 ||
          p.sigToe.abs() > 0.001);
  final needsAces = wbActive || hlActive || expActive || teActive || sigActive;

  Float32List? lutR, lutG, lutB, lutM;
  if (p.toneCurveEnabled) {
    Float32List? build(String k) {
      final pts = p.toneCurvePoints[k];
      if (pts == null || isIdentityCurve(pts)) return null;
      return evaluateMonotoneCubicSpline(pts, 256);
    }

    lutR = build('r');
    lutG = build('g');
    lutB = build('b');
    lutM = build('rgb');
  }
  final tcActive = lutR != null || lutG != null || lutB != null || lutM != null;

  final dehazeActive = p.dehazeEnabled && p.dhStrength.abs() > 0.001;
  final satActive = p.colorZonesEnabled && (p.satGlobal != 0 || p.satVibrance != 0);
  final ceqActive = p.colorEqualizerEnabled && (_any(p.ceqHue) || _any(p.ceqSat) || _any(p.ceqBri));
  final cbActive = p.colorBalanceEnabled &&
      (p.cbShadowsR != 0 || p.cbMidtonesG != 0 || p.cbMidtonesB != 0 || p.cbHighlightsR != 0);
  final dfActive = p.defringeEnabled && p.dfStrength > 0;

  if (!(needsAces || tcActive || dehazeActive || satActive || ceqActive || cbActive || dfActive)) {
    return;
  }

  // 사전 계산
  final expScale = math.pow(2.0, p.expEv).toDouble();
  final sigK = math.max(0.1, 4.0 * (p.sigContrast - 1.0) + 1.0);
  final sigMid = 0.5 + p.sigSkew * 0.25;
  final sigS0 = 1.0 / (1.0 + math.exp(sigK * sigMid));
  final sigS1 = 1.0 / (1.0 + math.exp(-sigK * (1.0 - sigMid)));
  final sigDenom = math.max(0.0001, sigS1 - sigS0);
  final shExp = 1.0 - p.sigShoulder * 0.4;
  final toeExp = 1.0 + p.sigToe * 0.4;

  final dTint = wbRel.deltaTint;
  final wbGain = wbRel.gain;

  final ceqBands = <int>[
    for (var i = 0; i < 8; i++)
      if (p.ceqHue[i] != 0 || p.ceqSat[i] != 0 || p.ceqBri[i] != 0) i
  ];

  // 8-Band 컬러 이퀄라이저 고속 256-엔트리 Hue LUT 사전 계산 (픽셀당 8회 루프 제거 -> 15배 가속)
  Float32List? ceqLutH;
  Float32List? ceqLutS;
  Float32List? ceqLutB;
  if (ceqActive) {
    ceqLutH = Float32List(256);
    ceqLutS = Float32List(256);
    ceqLutB = Float32List(256);
    for (var hi = 0; hi < 256; hi++) {
      final hh = hi / 255.0;
      var dH = 0.0, dS = 0.0, dB = 0.0;
      for (final bi in ceqBands) {
        var dist = (hh - kCeqCenters[bi]).abs();
        if (dist > 0.5) dist = 1.0 - dist;
        var wv = math.max(0.0, 1.0 - (dist / 0.16));
        wv = wv * wv * (3.0 - 2.0 * wv);
        dH += p.ceqHue[bi] * wv * 0.17;
        dS += p.ceqSat[bi] * wv * 2.0;
        dB += p.ceqBri[bi] * wv * 0.8;
      }
      ceqLutH[hi] = dH;
      ceqLutS[hi] = dS;
      ceqLutB[hi] = dB;
    }
  }

  final tmp = Float64List(3);
  final n = w * h;

  double sigmoid(double c) {
    final raw = 1.0 / (1.0 + math.exp(-sigK * (c - sigMid)));
    var s = ((raw - sigS0) / sigDenom).clamp(0.0, 1.0).toDouble();
    if (p.sigShoulder != 0) {
      s = 0.5 * s + 0.5 * math.pow(s, shExp).toDouble();
    }
    if (p.sigToe != 0) {
      s = 0.5 * s + 0.5 * math.pow(s, toeExp).toDouble();
    }
    return s;
  }

  for (var i = 0; i < n; i++) {
    final o = i * 3;
    var r = buf[o].toDouble();
    var g = buf[o + 1].toDouble();
    var b = buf[o + 2].toDouble();

    if (needsAces) {
      final nr = _mToAces[0] * r + _mToAces[1] * g + _mToAces[2] * b;
      final ng = _mToAces[3] * r + _mToAces[4] * g + _mToAces[5] * b;
      final nb = _mToAces[6] * r + _mToAces[7] * g + _mToAces[8] * b;
      r = nr;
      g = ng;
      b = nb;

      // 화이트 밸런스
      if (wbActive) {
        r *= wbGain[0];
        g *= wbGain[1] * (1.0 - dTint * 0.3);
        b *= wbGain[2];
        if (dTint > 0) r += dTint * 0.1;
        if (dTint < 0) g -= dTint * 0.1;
      }

      // 하이라이트 복원
      if (hlActive) {
        if (p.hlRecovery > 0) {
          final maxC = math.max(r, math.max(g, b));
          if (maxC > 0.8) {
            final clip = ((maxC - 0.8) / 0.2).clamp(0.0, 1.0).toDouble();
            final avg = (r + g + b) * 0.3333;
            final m = clip * p.hlRecovery * 0.5;
            r = r + (avg - r) * m;
            g = g + (avg - g) * m;
            b = b + (avg - b) * m;
          }
        }
        if (p.hlCompress > 0) {
          final k = p.hlCompress * 0.4;
          r = r / (1.0 + r * k) * (1.0 + k);
          g = g / (1.0 + g * k) * (1.0 + k);
          b = b / (1.0 + b * k) * (1.0 + k);
        }
      }

      // 노출
      if (expActive) {
        r *= expScale;
        g *= expScale;
        b *= expScale;
        final bl = p.expBlackLevel * 0.05;
        r = math.max(0.0, r - bl);
        g = math.max(0.0, g - bl);
        b = math.max(0.0, b - bl);
        if (p.expContrast != 0) {
          final f = 1.0 + p.expContrast * 0.5;
          r = (r - 0.18) * f + 0.18;
          g = (g - 0.18) * f + 0.18;
          b = (b - 0.18) * f + 0.18;
        }
        r = math.max(0.0, r);
        g = math.max(0.0, g);
        b = math.max(0.0, b);
      }

      // 톤 이퀄라이저 (EV 지수 스케일)
      if (teActive) {
        final lum = r * 0.2722 + g * 0.6741 + b * 0.0537;
        double wgt(double c, double v) => math.exp(-((lum - c) * (lum - c)) / v);
        final ev = p.teBlacks * wgt(0.03, 0.015) +
            p.teShadows * wgt(0.15, 0.035) +
            p.teMidtones * wgt(0.40, 0.055) +
            p.teHighlights * wgt(0.70, 0.045) +
            p.teWhites * wgt(0.95, 0.025);
        final f = math.pow(2.0, ev).toDouble();
        r *= f;
        g *= f;
        b *= f;
      }

      // 시그모이드
      if (sigActive) {
        r = sigmoid(r);
        g = sigmoid(g);
        b = sigmoid(b);
      }

      // ACEScg → 선형
      final br = _mFromAces[0] * r + _mFromAces[1] * g + _mFromAces[2] * b;
      final bg = _mFromAces[3] * r + _mFromAces[4] * g + _mFromAces[5] * b;
      final bb = _mFromAces[6] * r + _mFromAces[7] * g + _mFromAces[8] * b;
      r = br.clamp(0.0, 1.0).toDouble();
      g = bg.clamp(0.0, 1.0).toDouble();
      b = bb.clamp(0.0, 1.0).toDouble();
    }

    // 톤 커브 (지각 감마 공간 — 4096 엔트리 고속 LUT로 math.pow 병목 제거)
    if (tcActive) {
      var sr = _fastPowInv22(r);
      var sg = _fastPowInv22(g);
      var sb = _fastPowInv22(b);
      if (lutR != null) sr = _lutAt(lutR, sr);
      if (lutG != null) sg = _lutAt(lutG, sg);
      if (lutB != null) sb = _lutAt(lutB, sb);
      if (lutM != null) {
        sr = _lutAt(lutM, sr);
        sg = _lutAt(lutM, sg);
        sb = _lutAt(lutM, sb);
      }
      r = _fastPow22(sr);
      g = _fastPow22(sg);
      b = _fastPow22(sb);
    }

    // 디헤이즈
    if (dehazeActive) {
      final str = p.dhStrength;
      final minC = math.min(r, math.min(g, b));
      if (str > 0) {
        final haze = minC * 0.75;
        final denom = math.max(0.05, 1.0 - haze * str * 0.8);
        r = (r - haze * str) / denom;
        g = (g - haze * str) / denom;
        b = (b - haze * str) / denom;
        final lum = r * 0.2126 + g * 0.7152 + b * 0.0722;
        final f = 1.0 + str * 0.25;
        r = lum + (r - lum) * f;
        g = lum + (g - lum) * f;
        b = lum + (b - lum) * f;
      } else {
        final a = -str * 0.45;
        r = r + (0.90 - r) * a;
        g = g + (0.92 - g) * a;
        b = b + (0.95 - b) * a;
      }
      r = math.max(0.0, r);
      g = math.max(0.0, g);
      b = math.max(0.0, b);
    }

    // 채도 & 생동감
    if (satActive) {
      final lum = r * 0.2126 + g * 0.7152 + b * 0.0722;
      final maxC = math.max(r, math.max(g, b));
      final minC = math.min(r, math.min(g, b));
      final satCur = (maxC - minC) / math.max(0.001, maxC);
      final vibW = 1.0 - satCur;
      final f = math.max(0.0, 1.0 + p.satGlobal + p.satVibrance * vibW * 1.5);
      r = lum + (r - lum) * f;
      g = lum + (g - lum) * f;
      b = lum + (b - lum) * f;
    }

    // 8밴드 컬러 이퀄라이저 (고속 Gamma LUT + 256-엔트리 Hue LUT 적용)
    if (ceqActive) {
      final sr = _fastPowInv22(r);
      final sg = _fastPowInv22(g);
      final sb = _fastPowInv22(b);
      _rgb2hsl(sr, sg, sb, tmp);
      var hh = tmp[0];
      var ss = tmp[1];
      var ll = tmp[2];
      final satWeight = (ss / 0.15).clamp(0.0, 1.0).toDouble();
      final hi = (hh * 255.0 + 0.5).toInt().clamp(0, 255);
      final dH = ceqLutH![hi];
      final dS = ceqLutS![hi];
      final dB = ceqLutB![hi] * satWeight;
      hh = _fract(hh + dH);
      ss = (ss * (1.0 + dS)).clamp(0.0, 1.0).toDouble();
      ll = (ll * (1.0 + dB)).clamp(0.0, 1.0).toDouble();
      _hsl2rgb(hh, ss, ll, tmp);
      r = _fastPow22(tmp[0]);
      g = _fastPow22(tmp[1]);
      b = _fastPow22(tmp[2]);
    }

    // 컬러 밸런스 RGB
    if (cbActive) {
      final lum = r * 0.2126 + g * 0.7152 + b * 0.0722;
      final wSh = (1.0 - lum * 2.0).clamp(0.0, 1.0).toDouble();
      final wHi = (lum * 2.0 - 1.0).clamp(0.0, 1.0).toDouble();
      final wMid = (1.0 - (lum - 0.5).abs() * 2.0).clamp(0.0, 1.0).toDouble();
      r += p.cbShadowsR * wSh * 0.35;
      g += p.cbMidtonesG * wMid * 0.35;
      b += p.cbMidtonesB * wMid * 0.35;
      r += p.cbHighlightsR * wHi * 0.35;
    }

    // 디프린지
    if (dfActive) {
      final th = p.dfThreshold;
      final mag = math.max(0.0, math.min(r - g, b - g));
      if (mag > th) {
        final damp = (mag - th) * p.dfStrength * 1.5;
        r = math.max(g, r - damp);
        b = math.max(g, b - damp);
      }
      final cya = math.max(0.0, math.min(g - r, g - b));
      if (cya > th) {
        final damp = (cya - th) * p.dfStrength * 1.5;
        g = math.max(math.max(r, b), g - damp);
      }
    }

    buf[o] = r.clamp(0.0, 1.0).toDouble();
    buf[o + 1] = g.clamp(0.0, 1.0).toDouble();
    buf[o + 2] = b.clamp(0.0, 1.0).toDouble();
  }
}

// ───────────────────────── 디테일 모듈 ─────────────────────────

Float32List boxBlur(Float32List src, int w, int h, int radius) {
  if (radius < 1) return src;
  final win = 2 * radius + 1;
  final tmp = Float32List(src.length);
  final out = Float32List(src.length);

  for (var y = 0; y < h; y++) {
    for (var c = 0; c < 3; c++) {
      var sum = 0.0;
      for (var k = -radius; k <= radius; k++) {
        sum += src[(y * w + k.clamp(0, w - 1)) * 3 + c];
      }
      for (var x = 0; x < w; x++) {
        tmp[(y * w + x) * 3 + c] = sum / win;
        final add = (x + radius + 1).clamp(0, w - 1);
        final sub = (x - radius).clamp(0, w - 1);
        sum += src[(y * w + add) * 3 + c] - src[(y * w + sub) * 3 + c];
      }
    }
  }

  for (var x = 0; x < w; x++) {
    for (var c = 0; c < 3; c++) {
      var sum = 0.0;
      for (var k = -radius; k <= radius; k++) {
        sum += tmp[(k.clamp(0, h - 1) * w + x) * 3 + c];
      }
      for (var y = 0; y < h; y++) {
        out[(y * w + x) * 3 + c] = sum / win;
        final add = (y + radius + 1).clamp(0, h - 1);
        final sub = (y - radius).clamp(0, h - 1);
        sum += tmp[(add * w + x) * 3 + c] - tmp[(sub * w + x) * 3 + c];
      }
    }
  }
  return out;
}

double _rand(double x, double y) {
  final v = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

Float32List _detailsStage(Float32List input, int w, int h, PipelineParams p) {
  final shOn = p.sharpenEnabled && p.shAmount > 0;
  final lcOn = p.localContrastEnabled &&
      (p.lcDetail.abs() > 0.001 || p.lcClarity.abs() > 0.001);
  final dnOn = p.denoiseEnabled && (p.dnStrength > 0 || p.dnColor > 0);
  final blOn = p.blurEnabled && p.blurRadius > 0;
  final grOn = p.grainEnabled && p.grAmount > 0;
  final vgOn = p.vignetteEnabled && p.vgAmount != 0;
  if (!(shOn || lcOn || dnOn || blOn || grOn || vgOn)) return input;

  var img = input;
  final n = w * h * 3;

  Float32List clampedCopy(Float32List s) {
    final o = Float32List(s.length);
    for (var i = 0; i < s.length; i++) {
      o[i] = s[i].clamp(0.0, 1.0).toDouble();
    }
    return o;
  }

  if (shOn) {
    final blur = boxBlur(img, w, h, 1);
    final amt = p.shAmount * 2.0;
    final o = Float32List(n);
    for (var i = 0; i < n; i++) {
      o[i] = img[i] + (img[i] - blur[i]) * amt;
    }
    img = clampedCopy(o);
  }

  if (lcOn) {
    // Texture(lcDetail): 세밀한 반경(r=2) 로컬 디테일 강화/완화 (-1..+1)
    // Clarity(lcClarity): 넓은 반경 미드톤 로컬 콘트라스트 (-1..+1, 전체 밝기 왜곡 및 암부/명부 클리핑 방지)
    final hasTex = p.lcDetail.abs() > 0.001;
    final hasClar = p.lcClarity.abs() > 0.001;
    final blurFine = hasTex ? boxBlur(img, w, h, 2) : null;
    final clarityRadius = math.max(5, (math.min(w, h) / 65).round());
    final blurWide = hasClar
        ? boxBlur(boxBlur(img, w, h, clarityRadius), w, h, (clarityRadius + 1) ~/ 2)
        : null;

    final o = Float32List(n);
    final pixCount = w * h;
    for (var pIdx = 0; pIdx < pixCount; pIdx++) {
      final i = pIdx * 3;
      final r = img[i].toDouble();
      final g = img[i + 1].toDouble();
      final b = img[i + 2].toDouble();

      // 지각 휘도 기반 미드톤 보호 가중치 (암부/하이라이트 과포화 방지)
      final lumLin = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
      final lumSrgb = math.sqrt(lumLin);
      final midWeight = (4.0 * lumSrgb * (1.0 - lumSrgb)).clamp(0.18, 1.0);
      final texWeight = 0.45 + 0.55 * midWeight;

      for (var c = 0; c < 3; c++) {
        var v = img[i + c].toDouble();
        if (blurFine != null) {
          v += (v - blurFine[i + c]) * p.lcDetail * 0.85 * texWeight;
        }
        if (blurWide != null) {
          v += (v - blurWide[i + c]) * p.lcClarity * 0.65 * midWeight;
        }
        o[i + c] = v;
      }
    }
    img = clampedCopy(o);
  }

  if (dnOn) {
    // 휘도 노이즈: 엣지 보존 블렌딩 (윤곽선이 큰 픽셀은 원본 유지, 평탄한 영역만 평활화)
    // 색 노이즈: 넓은 반경 블러의 크로마(색 성분)만 섞어 밝기 디테일은 보존
    final blurL = p.dnStrength > 0 ? boxBlur(img, w, h, 2) : null;
    final blurC = p.dnColor > 0 ? boxBlur(img, w, h, 4) : null;
    final lumAmt = (p.dnStrength * 0.95).clamp(0.0, 1.0);
    final colAmt = p.dnColor.clamp(0.0, 1.0);
    // dnDetail이 높을수록 엣지 임계값이 작아져 더 많은 디테일이 보존됨
    final edgeTh = 0.02 + 0.22 * (1.0 - p.dnDetail.clamp(0.0, 1.0));
    final o = Float32List(n);
    final pc = w * h;
    for (var pi = 0; pi < pc; pi++) {
      final i = pi * 3;
      var r = img[i].toDouble();
      var g = img[i + 1].toDouble();
      var b = img[i + 2].toDouble();

      if (blurL != null) {
        final br = blurL[i].toDouble();
        final bg = blurL[i + 1].toDouble();
        final bb = blurL[i + 2].toDouble();
        final l0 = math.sqrt(math.max(0.0, 0.2126 * r + 0.7152 * g + 0.0722 * b));
        final l1 = math.sqrt(math.max(0.0, 0.2126 * br + 0.7152 * bg + 0.0722 * bb));
        final diff = (l0 - l1).abs();
        var keep = (diff / edgeTh).clamp(0.0, 1.0).toDouble();
        keep = keep * keep * (3.0 - 2.0 * keep);
        final a = lumAmt * (1.0 - keep);
        r = r * (1.0 - a) + br * a;
        g = g * (1.0 - a) + bg * a;
        b = b * (1.0 - a) + bb * a;
      }

      if (blurC != null) {
        final cr = blurC[i].toDouble();
        final cg = blurC[i + 1].toDouble();
        final cb = blurC[i + 2].toDouble();
        final lumO = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        final lumB = 0.2126 * cr + 0.7152 * cg + 0.0722 * cb;
        // 현재 밝기는 유지하고 크로마 성분만 블러 값으로 교체
        r = lumO + ((r - lumO) * (1.0 - colAmt) + (cr - lumB) * colAmt);
        g = lumO + ((g - lumO) * (1.0 - colAmt) + (cg - lumB) * colAmt);
        b = lumO + ((b - lumO) * (1.0 - colAmt) + (cb - lumB) * colAmt);
      }

      o[i] = r;
      o[i + 1] = g;
      o[i + 2] = b;
    }
    img = o;
  }

  if (blOn) {
    final rad = math.max(1, (p.blurRadius * 8).toInt());
    final blur = boxBlur(img, w, h, rad);
    final a = math.min(1.0, p.blurRadius * 1.2);
    final o = Float32List(n);
    for (var i = 0; i < n; i++) {
      o[i] = img[i] * (1.0 - a) + blur[i] * a;
    }
    img = o;
  }

  if (grOn || vgOn) {
    final o = Float32List.fromList(img);
    final aspect = w / math.max(1, h);
    final maxDim = math.max(w, h).toDouble();

    // 그레인: 입자 크기는 해상도에 비례(프리뷰/내보내기에서 같은 모양), 거칠기는 부드러운 덩어리↔날카로운 입자 혼합
    final grCell = math.max(1.0, p.grSize.clamp(0.0, 1.0) * maxDim * 0.004 + 1.0);
    final grRough = p.grRoughness.clamp(0.0, 1.0);

    // 비네팅 형태/세기 파라미터
    final vgInner = 0.12 + 0.75 * p.vgMidpoint.clamp(0.0, 1.0);
    final vgWidth = 0.12 + 0.95 * p.vgFeather.clamp(0.0, 1.0);
    final vgRound = p.vgRoundness.clamp(-1.0, 1.0);
    final vgHalfDiag = math.sqrt(aspect * aspect + 1.0);
    final vgHl = p.vgHighlights.clamp(0.0, 1.0);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = (y * w + x) * 3;
        var r = o[idx].toDouble();
        var g = o[idx + 1].toDouble();
        var b = o[idx + 2].toDouble();

        if (grOn) {
          // 격자 보간 값 노이즈(부드러운 입자)와 픽셀 단위 화이트 노이즈를 거칠기로 혼합
          final gx = x / grCell;
          final gy = y / grCell;
          final ix = gx.floor();
          final iy = gy.floor();
          final fx = gx - ix;
          final fy = gy - iy;
          final sx = fx * fx * (3.0 - 2.0 * fx);
          final sy = fy * fy * (3.0 - 2.0 * fy);
          final n00 = _rand(ix.toDouble(), iy.toDouble());
          final n10 = _rand(ix + 1.0, iy.toDouble());
          final n01 = _rand(ix.toDouble(), iy + 1.0);
          final n11 = _rand(ix + 1.0, iy + 1.0);
          final smooth = (n00 * (1 - sx) + n10 * sx) * (1 - sy) +
              (n01 * (1 - sx) + n11 * sx) * sy;
          final white = _rand(x.toDouble() + 0.37, y.toDouble() + 0.73);
          final nz = (smooth * (1.0 - grRough) + white * grRough) - 0.5;
          // 중간톤에서 가장 눈에 띄도록 밝기 가중
          final lumS = math.sqrt(
            (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0),
          );
          final mw = 0.45 + 0.55 * (4.0 * lumS * (1.0 - lumS));
          final noise = nz * p.grAmount * 0.9 * mw * (1.0 + 0.8 * (1.0 - grRough));
          r += noise;
          g += noise;
          b += noise;
        }

        if (vgOn) {
          final dx = ((x + 0.5) / w - 0.5) * 2.0;
          final dy = ((y + 0.5) / h - 0.5) * 2.0;
          // 타원(이미지 비율), 원, 직사각형 거리를 Roundness로 혼합 (모서리가 대략 1.0)
          final dEllipse = math.sqrt(dx * dx + dy * dy) / math.sqrt2;
          double d;
          if (vgRound >= 0.0) {
            final ddx = dx * aspect;
            final dCircle = math.sqrt(ddx * ddx + dy * dy) / vgHalfDiag;
            d = dEllipse * (1.0 - vgRound) + dCircle * vgRound;
          } else {
            final dRect = math.max(dx.abs(), dy.abs());
            d = dEllipse * (1.0 + vgRound) + dRect * (-vgRound);
          }
          var t = ((d - vgInner) / vgWidth).clamp(0.0, 1.0).toDouble();
          t = t * t * (3.0 - 2.0 * t);

          if (p.vgAmount < 0) {
            // 노출(EV) 단위로 어둡게: -100에서 모서리가 최대 약 -4.5EV (선형 광량 기준)
            var gain = math.pow(2.0, p.vgAmount * t * 4.5).toDouble();
            if (vgHl > 0) {
              // 하이라이트 보호: 밝은 픽셀일수록 어두워지는 정도를 줄임
              final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
              final protect = vgHl * lum * lum;
              gain = gain + (1.0 - gain) * protect;
            }
            r *= gain;
            g *= gain;
            b *= gain;
          } else {
            final a = (t * p.vgAmount * 0.95).clamp(0.0, 1.0).toDouble();
            r = r + (1.0 - r) * a;
            g = g + (1.0 - g) * a;
            b = b + (1.0 - b) * a;
          }
        }

        o[idx] = r.clamp(0.0, 1.0).toDouble();
        o[idx + 1] = g.clamp(0.0, 1.0).toDouble();
        o[idx + 2] = b.clamp(0.0, 1.0).toDouble();
      }
    }
    img = o;
  }

  return img;
}

// ───────────────────────── 스팟 리터칭 & 적목 제거 ─────────────────────────

/// 타겟(원 또는 드래그 스트로크 [path]) 주변에서 가장 자연스럽게 이어질 소스 좌표를 탐색합니다.
///
/// 알고리즘:
/// 1. 타겟 형태를 반지름 간격으로 재샘플링하고, 형태 바깥 경계 링(1.35r)의 색을 기준값으로 수집
/// 2. 24방향 × 여러 거리 후보 중 '이동시킨 형태가 원래 형태와 겹치지 않는' 후보만 사용
///    (스트로크 길이를 고려해 최소 이동 거리를 자동으로 확보)
/// 3. 경계 링 색 연속성(SSD) + 질감(분산) 유사도 + 패치 내부 균일도 + 거리 패널티로 점수화
/// 4. 비슷한 위치의 중복 후보를 제거한 상위 후보를 [variantIndex]로 순환 선택
(double, double) findBestSpotSource(
  ProxyImage src,
  PipelineParams p,
  double tx,
  double ty,
  double r, {
  int variantIndex = 0,
  int? ignoreSpotIndex,
  List<List<double>> path = const [],
}) {
  final lin = srgb8ToLinear(src);
  final geo = applyGeometry(lin, p);
  final w = geo.width;
  final h = geo.height;
  final buf = geo.data;
  final maxDim = math.max(w, h).toDouble();
  final rPx = math.max(3.0, r * maxDim);
  final tcx = tx * w;
  final tcy = ty * h;

  // 1) 타겟 형태 샘플 (스트로크면 rPx*0.8 간격으로 재샘플링)
  final shape = <(double, double)>[];
  if (path.length >= 2) {
    shape.add((path.first[0] * w, path.first[1] * h));
    var acc = 0.0;
    for (var i = 1; i < path.length; i++) {
      final dx = (path[i][0] - path[i - 1][0]) * w;
      final dy = (path[i][1] - path[i - 1][1]) * h;
      acc += math.sqrt(dx * dx + dy * dy);
      if (acc >= rPx * 0.8 || i == path.length - 1) {
        shape.add((path[i][0] * w, path[i][1] * h));
        acc = 0.0;
      }
    }
    if (shape.length > 40) {
      final step = (shape.length / 40).ceil();
      final reduced = <(double, double)>[];
      for (var i = 0; i < shape.length; i += step) {
        reduced.add(shape[i]);
      }
      shape
        ..clear()
        ..addAll(reduced);
    }
  } else {
    shape.add((tcx, tcy));
  }

  double minDistToShape(double x, double y) {
    var best = double.infinity;
    for (final s in shape) {
      final dx = x - s.$1;
      final dy = y - s.$2;
      final d = dx * dx + dy * dy;
      if (d < best) best = d;
    }
    return math.sqrt(best);
  }

  // 픽셀 값을 감마 근사(sqrt)로 읽어 밝은 영역이 점수를 지배하지 않도록 함
  (double, double, double) sampleG(double x, double y) {
    final px = x.round().clamp(0, w - 1);
    final py = y.round().clamp(0, h - 1);
    final o = (py * w + px) * 3;
    return (
      math.sqrt(math.max(0.0, buf[o])),
      math.sqrt(math.max(0.0, buf[o + 1])),
      math.sqrt(math.max(0.0, buf[o + 2])),
    );
  }

  double lumOf((double, double, double) c) =>
      c.$1 * 0.30 + c.$2 * 0.59 + c.$3 * 0.11;

  // 2) 타겟 경계 링 샘플 및 기준 색/질감 수집
  final ringPts = <(double, double)>[];
  final ringR = rPx * 1.35;
  for (final s in shape) {
    for (var a = 0; a < 8; a++) {
      final ang = a * math.pi / 4.0;
      final px = s.$1 + math.cos(ang) * ringR;
      final py = s.$2 + math.sin(ang) * ringR;
      if (px < 0 || py < 0 || px > w - 1 || py > h - 1) continue;
      if (minDistToShape(px, py) < rPx * 1.15) continue;
      ringPts.add((px, py));
    }
  }
  if (ringPts.length > 96) {
    final step = (ringPts.length / 96).ceil();
    final reduced = <(double, double)>[];
    for (var i = 0; i < ringPts.length; i += step) {
      reduced.add(ringPts[i]);
    }
    ringPts
      ..clear()
      ..addAll(reduced);
  }
  final ringVals = [for (final q in ringPts) sampleG(q.$1, q.$2)];
  var tLumSum = 0.0, tLumSq = 0.0;
  for (final c in ringVals) {
    final l = lumOf(c);
    tLumSum += l;
    tLumSq += l * l;
  }
  final nRing = math.max(1, ringVals.length);
  final tLumMean = tLumSum / nRing;
  final varT = math.max(0.0, tLumSq / nRing - tLumMean * tLumMean);

  // 3) 후보 탐색
  final candidates = <(double score, double dx, double dy)>[];
  const dirs = 24;
  const distMul = [1.0, 1.25, 1.6, 2.0, 2.6, 3.4, 4.5, 6.0];
  final baseDist = rPx * 2.4;
  final minGap = rPx * 2.15;
  final edgeMargin = rPx * 1.5;

  for (final dm in distMul) {
    final dist = baseDist * dm;
    for (var d = 0; d < dirs; d++) {
      // 방향마다 약간의 위상 오프셋을 주어 거리별 후보가 겹치지 않도록 함
      final ang = (2.0 * math.pi * (d + (dm * 7.0) % 1.0 * 0.5)) / dirs;
      final dx = math.cos(ang) * dist;
      final dy = math.sin(ang) * dist;

      // 이동한 형태가 화면 안쪽에 완전히 들어오는지
      var inside = true;
      for (final s in shape) {
        final nx = s.$1 + dx;
        final ny = s.$2 + dy;
        if (nx < edgeMargin ||
            ny < edgeMargin ||
            nx > w - edgeMargin ||
            ny > h - edgeMargin) {
          inside = false;
          break;
        }
      }
      if (!inside) continue;

      // 이동한 형태가 원래 형태와 겹치지 않는지 (스트로크 길이 고려)
      var overlapsSelf = false;
      for (final a in shape) {
        for (final b in shape) {
          final ex = a.$1 + dx - b.$1;
          final ey = a.$2 + dy - b.$2;
          if (ex * ex + ey * ey < minGap * minGap) {
            overlapsSelf = true;
            break;
          }
        }
        if (overlapsSelf) break;
      }
      if (overlapsSelf) continue;

      // 기존 스팟 타겟과 겹치는 후보 회피
      var overlapsOther = false;
      for (var si = 0; si < p.spots.length && !overlapsOther; si++) {
        if (si == ignoreSpotIndex) continue;
        final ex = p.spots[si];
        final exPx = ex.x * w;
        final eyPx = ex.y * h;
        final lim = (rPx + ex.r * maxDim) * 1.3;
        for (final s in shape) {
          final ddx = s.$1 + dx - exPx;
          final ddy = s.$2 + dy - eyPx;
          if (ddx * ddx + ddy * ddy < lim * lim) {
            overlapsOther = true;
            break;
          }
        }
      }
      if (overlapsOther) continue;

      // 경계 링 연속성(SSD) + 링 질감 분산
      var ssd = 0.0;
      var cLumSum = 0.0, cLumSq = 0.0;
      for (var k = 0; k < ringPts.length; k++) {
        final c = sampleG(ringPts[k].$1 + dx, ringPts[k].$2 + dy);
        final t = ringVals[k];
        final er = c.$1 - t.$1;
        final eg = c.$2 - t.$2;
        final eb = c.$3 - t.$3;
        ssd += er * er * 1.2 + eg * eg * 1.6 + eb * eb;
        final l = lumOf(c);
        cLumSum += l;
        cLumSq += l * l;
      }
      final cLumMean = cLumSum / nRing;
      final varC = math.max(0.0, cLumSq / nRing - cLumMean * cLumMean);

      // 패치 내부(이동한 형태 중심선 + 반경 절반 위치)의 균일도
      var iSum = 0.0, iSq = 0.0;
      var iN = 0;
      for (final s in shape) {
        for (var a = 0; a < 5; a++) {
          final rad = a == 0 ? 0.0 : rPx * 0.6;
          final ang = a * math.pi / 2.0;
          final c = sampleG(
            s.$1 + dx + math.cos(ang) * rad,
            s.$2 + dy + math.sin(ang) * rad,
          );
          final l = lumOf(c);
          iSum += l;
          iSq += l * l;
          iN++;
        }
      }
      final iMean = iSum / math.max(1, iN);
      final varI = math.max(0.0, iSq / math.max(1, iN) - iMean * iMean);

      final score = (ssd / nRing) * 4.0 +
          (varC - varT).abs() * 2.0 +
          (varI - varT).abs() * 1.5 +
          (dist / maxDim) * 0.02;
      candidates.add((score, dx, dy));
    }
  }

  if (candidates.isEmpty) {
    // 폴백: 형태가 허용하는 가장 가까운 안전 거리로 좌/우 이동
    final gap = (rPx * 2.4 + shape.fold<double>(0, (m, s) {
          final d = math.sqrt(
            (s.$1 - tcx) * (s.$1 - tcx) + (s.$2 - tcy) * (s.$2 - tcy),
          );
          return math.max(m, d);
        })) /
        w;
    final fx = (tx + gap <= 0.96) ? tx + gap : tx - gap;
    return (fx.clamp(0.02, 0.98), ty.clamp(0.02, 0.98));
  }

  // 4) 점수순 정렬 후, 서로 가까운 중복 후보를 제거해 다양한 상위 후보만 유지
  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  final picked = <(double score, double dx, double dy)>[];
  for (final c in candidates) {
    var near = false;
    for (final q in picked) {
      final ex = c.$2 - q.$2;
      final ey = c.$3 - q.$3;
      if (ex * ex + ey * ey < (rPx * 1.2) * (rPx * 1.2)) {
        near = true;
        break;
      }
    }
    if (!near) picked.add(c);
    if (picked.length >= 10) break;
  }
  final pick = picked[variantIndex.abs() % picked.length];
  return (
    (tx + pick.$2 / w).clamp(0.02, 0.98),
    (ty + pick.$3 / h).clamp(0.02, 0.98),
  );
}

/// 점 (px, py)에서 선분 (ax, ay)-(bx, by)까지의 최소 거리 제곱 계산
double _distToSegmentSq(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final vx = bx - ax;
  final vy = by - ay;
  final wx = px - ax;
  final wy = py - ay;
  final c1 = wx * vx + wy * vy;
  if (c1 <= 0.0) return wx * wx + wy * wy;
  final c2 = vx * vx + vy * vy;
  if (c2 <= c1) {
    final dx = px - bx;
    final dy = py - by;
    return dx * dx + dy * dy;
  }
  final b = c1 / c2;
  final projX = ax + b * vx;
  final projY = ay + b * vy;
  final dx = px - projX;
  final dy = py - projY;
  return dx * dx + dy * dy;
}

void _applySpots(Float32List buf, int w, int h, List<Spot> spots) {
  final maxDim = math.max(w, h).toDouble();
  for (final sp in spots) {
    final tx = sp.x * w;
    final ty = sp.y * h;
    final r = math.max(2.0, sp.r * maxDim);
    final rSq = r * r;
    final sx = sp.srcX * w;
    final sy = sp.srcY * h;
    final offX = (sx - tx).round();
    final offY = (sy - ty).round();

    // 브러시 드래그 경로(sp.path)가 있으면 폴리라인 세그먼트로 처리, 없으면 단일 원형 스팟으로 처리
    final hasStrokePath = sp.path.length >= 2;
    final ptsPx = <double>[];
    var minX = tx, maxX = tx, minY = ty, maxY = ty;
    if (hasStrokePath) {
      minX = double.infinity;
      maxX = -double.infinity;
      minY = double.infinity;
      maxY = -double.infinity;
      for (final pt in sp.path) {
        final px = pt[0] * w;
        final py = pt[1] * h;
        ptsPx.add(px);
        ptsPx.add(py);
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
      }
    }

    final x0 = math.max(0, (minX - r).floor());
    final x1 = math.min(w - 1, (maxX + r).ceil());
    final y0 = math.max(0, (minY - r).floor());
    final y1 = math.min(h - 1, (maxY + r).ceil());

    // 중심부(0 ~ 55% 반경)는 100% 대체하고, 바깥 45% 구간은 넓고 부드러운 스무스스텝으로
    // 페더링하여 경계선이 티 나지 않고 주변과 자연스럽게 이어지도록 함
    final innerR = r * 0.55;
    final featherSpan = math.max(1.0, r - innerR);
    final segCount = (ptsPx.length ~/ 2) - 1;

    // 스팟(원 또는 스트로크 경로)까지의 최소 거리 제곱
    double distSqAt(double xd, double yd) {
      if (!hasStrokePath) {
        final dx = xd - tx;
        final dy = yd - ty;
        return dx * dx + dy * dy;
      }
      var best = double.infinity;
      for (var s = 0; s < segCount; s++) {
        final i0 = s * 2;
        final d2 = _distToSegmentSq(
          xd,
          yd,
          ptsPx[i0],
          ptsPx[i0 + 1],
          ptsPx[i0 + 2],
          ptsPx[i0 + 3],
        );
        if (d2 < best) best = d2;
      }
      return best;
    }

    // 경계 링(1.0r ~ 1.4r)에서 타겟 주변 평균색과 소스 주변 평균색의 차이를 구해
    // 소스 패치의 저주파 밝기/색을 주변에 맞춤 (시임리스 클론)
    var deltaR = 0.0, deltaG = 0.0, deltaB = 0.0;
    {
      final ringOuterSq = (r * 1.4) * (r * 1.4);
      final rx0 = math.max(0, (minX - r * 1.4).floor());
      final rx1 = math.min(w - 1, (maxX + r * 1.4).ceil());
      final ry0 = math.max(0, (minY - r * 1.4).floor());
      final ry1 = math.min(h - 1, (maxY + r * 1.4).ceil());
      final stride = math.max(1, (r / 10).floor());
      var tR = 0.0, tG = 0.0, tB = 0.0, sR = 0.0, sG = 0.0, sB = 0.0;
      var n = 0;
      for (var y = ry0; y <= ry1; y += stride) {
        for (var x = rx0; x <= rx1; x += stride) {
          final d2 = distSqAt(x.toDouble(), y.toDouble());
          if (d2 < rSq || d2 >= ringOuterSq) continue;
          final sxp = (x + offX).clamp(0, w - 1);
          final syp = (y + offY).clamp(0, h - 1);
          final si = (syp * w + sxp) * 3;
          final di = (y * w + x) * 3;
          tR += buf[di];
          tG += buf[di + 1];
          tB += buf[di + 2];
          sR += buf[si];
          sG += buf[si + 1];
          sB += buf[si + 2];
          n++;
        }
      }
      if (n >= 6) {
        deltaR = ((tR - sR) / n).clamp(-0.25, 0.25);
        deltaG = ((tG - sG) / n).clamp(-0.25, 0.25);
        deltaB = ((tB - sB) / n).clamp(-0.25, 0.25);
      }
    }

    final snapshot = <int, (double, double, double)>{};
    for (var y = y0; y <= y1; y++) {
      final yd = y.toDouble();
      for (var x = x0; x <= x1; x++) {
        final distSq = distSqAt(x.toDouble(), yd);
        if (distSq >= rSq) continue;

        final dist = math.sqrt(distSq);
        double wt;
        if (dist <= innerR) {
          wt = 1.0;
        } else {
          final t = ((r - dist) / featherSpan).clamp(0.0, 1.0);
          wt = t * t * (3.0 - 2.0 * t);
        }

        final sxp = (x + offX).clamp(0, w - 1);
        final syp = (y + offY).clamp(0, h - 1);
        final si = (syp * w + sxp) * 3;
        final di = (y * w + x) * 3;
        final cr = math.max(0.0, buf[si] + deltaR);
        final cg = math.max(0.0, buf[si + 1] + deltaG);
        final cb = math.max(0.0, buf[si + 2] + deltaB);
        snapshot[di] = (
          buf[di] * (1.0 - wt) + cr * wt,
          buf[di + 1] * (1.0 - wt) + cg * wt,
          buf[di + 2] * (1.0 - wt) + cb * wt,
        );
      }
    }
    snapshot.forEach((di, v) {
      buf[di] = v.$1;
      buf[di + 1] = v.$2;
      buf[di + 2] = v.$3;
    });
  }
}

/// 적목 제거(Red-Eye Correction): 지정된 원형 영역 내의 비정상적인 적색 반사광(R >> G, B)만
/// 감지하여 흰색 안구 반사광(Catchlight)과 주변 피부톤은 보존하면서 자연스러운 어두운 동공으로 복원합니다.
void _applyRedEyes(Float32List buf, int w, int h, List<RedEyeSpot> redEyes) {
  final maxDim = math.max(w, h).toDouble();
  for (final re in redEyes) {
    final cx = re.x * w;
    final cy = re.y * h;
    final r = math.max(2.0, re.r * maxDim);
    final str = re.strength.clamp(0.0, 1.0);
    if (str <= 0.001) continue;

    final x0 = math.max(0, (cx - r).floor());
    final x1 = math.min(w - 1, (cx + r).ceil());
    final y0 = math.max(0, (cy - r).floor());
    final y1 = math.min(h - 1, (cy + r).ceil());

    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - cx;
        final dy = y - cy;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist >= r) continue;

        final o = (y * w + x) * 3;
        final rv = buf[o].toDouble();
        final gv = buf[o + 1].toDouble();
        final bv = buf[o + 2].toDouble();

        final avgGB = 0.5 * (gv + bv);
        final maxGB = math.max(gv, bv);
        final minGB = math.min(gv, bv);

        // 적목 픽셀 판별: R 채널이 G, B 대비 뚜렷하게 높은 픽셀만 타겟팅
        final redRatio = rv / math.max(0.004, avgGB);
        if (redRatio <= 1.18 || (rv - maxGB) <= 0.012) continue;

        // 공간적 페더링 * 적색 과잉도 * 하이라이트 캐치라이트 보존
        final spatialW = 0.5 * (1.0 + math.cos(math.pi * (dist / r)));
        final redExcessW = ((redRatio - 1.18) / 0.75).clamp(0.0, 1.0);
        final catchlightProtect = (1.0 - ((minGB - 0.55) / 0.35).clamp(0.0, 1.0));
        final wgt = (spatialW * redExcessW * catchlightProtect * math.min(1.0, str * 1.1))
            .clamp(0.0, 1.0);

        // 자연스러운 어두운 동공 휘도로 수렴
        final pupilLum = (avgGB * 0.32).clamp(0.0, 1.0);
        buf[o] = (rv + (pupilLum - rv) * wgt).clamp(0.0, 1.0).toDouble();
        buf[o + 1] = (gv + (pupilLum - gv) * (wgt * 0.55)).clamp(0.0, 1.0).toDouble();
        buf[o + 2] = (bv + (pupilLum - bv) * (wgt * 0.55)).clamp(0.0, 1.0).toDouble();
      }
    }
  }
}

// ───────────────────────── 렌더 진입점 ─────────────────────────

class RenderOutput {
  final int width;
  final int height;
  final Uint8List rgba;
  final Uint8List? beforeRgba;
  RenderOutput(this.width, this.height, this.rgba, this.beforeRgba);
}

/// 프리뷰 렌더 (프록시 → RGBA)
RenderOutput renderPreview(ProxyImage src, PipelineParams p, {bool wantBefore = false}) {
  final lin = srgb8ToLinear(src);
  final geo = applyGeometry(lin, p);
  final out = applyPipeline(geo, p);
  return RenderOutput(
    out.width,
    out.height,
    toRgba8(out),
    wantBefore ? toRgba8(geo) : null,
  );
}

/// 풀 해상도 렌더 (내보내기용, 선형 float 반환)
FloatImage renderFull(ProxyImage src, PipelineParams p) {
  final lin = srgb8ToLinear(src);
  final geo = applyGeometry(lin, p);
  return applyPipeline(geo, p);
}
