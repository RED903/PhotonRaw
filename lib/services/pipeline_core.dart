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
  final dnOn = p.denoiseEnabled && p.dnStrength > 0;
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
    final blur = boxBlur(img, w, h, 2);
    final a = p.dnStrength * 0.6;
    final o = Float32List(n);
    for (var i = 0; i < n; i++) {
      o[i] = img[i] * (1.0 - a) + blur[i] * a;
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
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = (y * w + x) * 3;
        var r = o[idx].toDouble();
        var g = o[idx + 1].toDouble();
        var b = o[idx + 2].toDouble();

        if (grOn) {
          final noise = (_rand(x.toDouble(), y.toDouble()) - 0.5) * p.grAmount * 0.35;
          r += noise;
          g += noise;
          b += noise;
        }

        if (vgOn) {
          final dx = ((x + 0.5) / w - 0.5) * aspect;
          final dy = (y + 0.5) / h - 0.5;
          final len2 = dx * dx + dy * dy;
          if (p.vgAmount < 0) {
            final vig = (1.0 - len2 * (-p.vgAmount * 0.8)).clamp(0.0, 1.0).toDouble();
            r *= vig;
            g *= vig;
            b *= vig;
          } else {
            final vig = (len2 * (p.vgAmount * 0.8)).clamp(0.0, 1.0).toDouble();
            final a = vig * 0.75;
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

/// 타겟 위치 (tx, ty) 주변에서 경계 색상/휘도 연속성과 패치 내부 균일도가 가장 뛰어난 최적의 소스 좌표를 탐색합니다.
/// [variantIndex]를 증가시키면 차선책 후보들을 순환하며 선택할 수 있습니다.
(double, double) findBestSpotSource(
  ProxyImage src,
  PipelineParams p,
  double tx,
  double ty,
  double r, {
  int variantIndex = 0,
  int? ignoreSpotIndex,
}) {
  final lin = srgb8ToLinear(src);
  final geo = applyGeometry(lin, p);
  final w = geo.width;
  final h = geo.height;
  final buf = geo.data;
  final maxDim = math.max(w, h).toDouble();
  final rPx = math.max(3.0, r * maxDim);

  // 타겟 외곽 링(1.05r ~ 1.35r)의 평균 색상 샘플링 (잡티 중심부 오염 배제)
  var tR = 0.0, tG = 0.0, tB = 0.0;
  var tCount = 0;
  const ringSamples = 16;
  for (var i = 0; i < ringSamples; i++) {
    final ang = (2.0 * math.pi * i) / ringSamples;
    final sx = (tx * w + math.cos(ang) * rPx * 1.15).round().clamp(0, w - 1);
    final sy = (ty * h + math.sin(ang) * rPx * 1.15).round().clamp(0, h - 1);
    final o = (sy * w + sx) * 3;
    tR += buf[o];
    tG += buf[o + 1];
    tB += buf[o + 2];
    tCount++;
  }
  if (tCount > 0) {
    tR /= tCount;
    tG /= tCount;
    tB /= tCount;
  }

  final margin = (r * 1.3).clamp(0.02, 0.25);
  final candidates = <(double score, double cx, double cy)>[];
  final distMultipliers = [2.2, 3.2, 4.5, 6.0];
  const dirs = 16;

  for (final dm in distMultipliers) {
    final distNorm = (r * dm).clamp(0.025, 0.35);
    for (var d = 0; d < dirs; d++) {
      final ang = (2.0 * math.pi * d) / dirs;
      final aspect = w / math.max(1.0, h.toDouble());
      final cx = tx + math.cos(ang) * distNorm / math.max(1.0, aspect);
      final cy = ty + math.sin(ang) * distNorm * math.min(1.0, aspect);

      if (cx < margin || cx > 1.0 - margin || cy < margin || cy > 1.0 - margin) {
        continue;
      }

      // 기존 스팟 타겟 영역과 겹치는 후보는 회피
      var overlaps = false;
      for (var si = 0; si < p.spots.length; si++) {
        if (si == ignoreSpotIndex) continue;
        final ex = p.spots[si];
        final dx = cx - ex.x;
        final dy = cy - ex.y;
        if (math.sqrt(dx * dx + dy * dy) < (r + ex.r) * 1.3) {
          overlaps = true;
          break;
        }
      }
      if (overlaps) continue;

      // 후보 패치의 평균 색상 및 내부 분산(평탄도) 계산
      var cR = 0.0, cG = 0.0, cB = 0.0;
      var cR2 = 0.0, cG2 = 0.0, cB2 = 0.0;
      var cnt = 0;
      for (var ring = 0; ring <= 2; ring++) {
        final rad = rPx * (ring * 0.45);
        final steps = ring == 0 ? 1 : 8;
        for (var k = 0; k < steps; k++) {
          final a = (2.0 * math.pi * k) / steps;
          final px = (cx * w + math.cos(a) * rad).round().clamp(0, w - 1);
          final py = (cy * h + math.sin(a) * rad).round().clamp(0, h - 1);
          final o = (py * w + px) * 3;
          final vr = buf[o].toDouble();
          final vg = buf[o + 1].toDouble();
          final vb = buf[o + 2].toDouble();
          cR += vr;
          cG += vg;
          cB += vb;
          cR2 += vr * vr;
          cG2 += vg * vg;
          cB2 += vb * vb;
          cnt++;
        }
      }
      if (cnt == 0) continue;
      cR /= cnt;
      cG /= cnt;
      cB /= cnt;
      final varR = math.max(0.0, cR2 / cnt - cR * cR);
      final varG = math.max(0.0, cG2 / cnt - cG * cG);
      final varB = math.max(0.0, cB2 / cnt - cB * cB);
      final internalVariance = varR + varG + varB;

      // 타겟 주변부와의 색/휘도 차이
      final dr = cR - tR;
      final dg = cG - tG;
      final db = cB - tB;
      final colorDiff = dr * dr * 1.2 + dg * dg * 1.6 + db * db * 1.0;

      // 가까울수록 약간의 가산점, 평탄하고 색이 비슷할수록 낮은 점수(우수)
      final score = colorDiff * 3.0 + internalVariance * 1.8 + dm * 0.0015;
      candidates.add((score, cx.clamp(0.02, 0.98), cy.clamp(0.02, 0.98)));
    }
  }

  if (candidates.isEmpty) {
    final fallbackX = (tx + r * 2.4 <= 0.96) ? tx + r * 2.4 : tx - r * 2.4;
    return (fallbackX.clamp(0.02, 0.98), ty.clamp(0.02, 0.98));
  }

  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  final topK = math.min(12, candidates.length);
  final pick = candidates[variantIndex.abs() % topK];
  return (pick.$2, pick.$3);
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

    // 선택된 원/스트로크 내부(0 ~ 80% 반경)는 100% 완전 대체(wt = 1.0)하고,
    // 가장자리 외곽 20% 테두리만 부드럽게 페더링하여 뭉개짐 없이 선명하게 대체
    final innerR = r * 0.80;
    final featherSpan = math.max(1.0, r - innerR);
    final segCount = (ptsPx.length ~/ 2) - 1;

    final snapshot = <int, (double, double, double)>{};
    for (var y = y0; y <= y1; y++) {
      final yd = y.toDouble();
      for (var x = x0; x <= x1; x++) {
        final xd = x.toDouble();
        double distSq;
        if (!hasStrokePath) {
          final dx = xd - tx;
          final dy = yd - ty;
          distSq = dx * dx + dy * dy;
        } else {
          distSq = double.infinity;
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
            if (d2 < distSq) distSq = d2;
          }
        }
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
        snapshot[di] = (
          buf[di] * (1.0 - wt) + buf[si] * wt,
          buf[di + 1] * (1.0 - wt) + buf[si + 1] * wt,
          buf[di + 2] * (1.0 - wt) + buf[si + 2] * wt,
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
