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

    // 톤 커브 (지각 감마 공간)
    if (tcActive) {
      var sr = math.pow(r.clamp(0.0, 1.0), 1.0 / 2.2).toDouble();
      var sg = math.pow(g.clamp(0.0, 1.0), 1.0 / 2.2).toDouble();
      var sb = math.pow(b.clamp(0.0, 1.0), 1.0 / 2.2).toDouble();
      if (lutR != null) sr = _lutAt(lutR, sr);
      if (lutG != null) sg = _lutAt(lutG, sg);
      if (lutB != null) sb = _lutAt(lutB, sb);
      if (lutM != null) {
        sr = _lutAt(lutM, sr);
        sg = _lutAt(lutM, sg);
        sb = _lutAt(lutM, sb);
      }
      r = math.pow(sr.clamp(0.0, 1.0), 2.2).toDouble();
      g = math.pow(sg.clamp(0.0, 1.0), 2.2).toDouble();
      b = math.pow(sb.clamp(0.0, 1.0), 2.2).toDouble();
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

    // 8밴드 컬러 이퀄라이저
    if (ceqActive) {
      final sr = math.pow(r.clamp(0.0, 1.0), 1.0 / 2.2).toDouble();
      final sg = math.pow(g.clamp(0.0, 1.0), 1.0 / 2.2).toDouble();
      final sb = math.pow(b.clamp(0.0, 1.0), 1.0 / 2.2).toDouble();
      _rgb2hsl(sr, sg, sb, tmp);
      var hh = tmp[0];
      var ss = tmp[1];
      var ll = tmp[2];
      final satWeight = (ss / 0.15).clamp(0.0, 1.0).toDouble();
      var dH = 0.0, dS = 0.0, dB = 0.0;
      for (final bi in ceqBands) {
        var dist = (hh - kCeqCenters[bi]).abs();
        if (dist > 0.5) dist = 1.0 - dist;
        var wv = math.max(0.0, 1.0 - (dist / 0.16));
        wv = wv * wv * (3.0 - 2.0 * wv);
        dH += p.ceqHue[bi] * wv * 0.17;
        dS += p.ceqSat[bi] * wv * 2.0;
        dB += p.ceqBri[bi] * wv * 0.8 * satWeight;
      }
      hh = _fract(hh + dH);
      ss = (ss * (1.0 + dS)).clamp(0.0, 1.0).toDouble();
      ll = (ll * (1.0 + dB)).clamp(0.0, 1.0).toDouble();
      _hsl2rgb(hh, ss, ll, tmp);
      r = math.pow(tmp[0].clamp(0.0, 1.0), 2.2).toDouble();
      g = math.pow(tmp[1].clamp(0.0, 1.0), 2.2).toDouble();
      b = math.pow(tmp[2].clamp(0.0, 1.0), 2.2).toDouble();
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
  final lcOn = p.localContrastEnabled && (p.lcDetail > 0 || p.lcClarity != 0);
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
    final blur = boxBlur(img, w, h, 3);
    final o = Float32List(n);
    for (var i = 0; i < n; i++) {
      var v = img[i].toDouble();
      if (p.lcDetail > 0) v += (v - blur[i]) * p.lcDetail * 1.5;
      if (p.lcClarity != 0) v = (v - 0.5) * (1.0 + p.lcClarity * 0.5) + 0.5;
      o[i] = v;
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

// ───────────────────────── 스팟 리터칭 ─────────────────────────

void _applySpots(Float32List buf, int w, int h, List<Spot> spots) {
  for (final sp in spots) {
    final tx = sp.x * w;
    final ty = sp.y * h;
    final r = math.max(2.0, sp.r * math.max(w, h));
    final sx = sp.srcX * w;
    final sy = sp.srcY * h;
    final offX = (sx - tx).round();
    final offY = (sy - ty).round();

    final x0 = math.max(0, (tx - r).floor());
    final x1 = math.min(w - 1, (tx + r).ceil());
    final y0 = math.max(0, (ty - r).floor());
    final y1 = math.min(h - 1, (ty + r).ceil());

    // 겹치는 복제로 인한 오염을 막기 위해 원본 스냅샷 사용
    final snapshot = <int, List<double>>{};
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - tx;
        final dy = y - ty;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist >= r) continue;
        var wt = ((r - dist) / math.max(1.0, r * 0.35)).clamp(0.0, 1.0).toDouble();
        wt = wt * wt * (3.0 - 2.0 * wt);
        final sxp = (x + offX).clamp(0, w - 1);
        final syp = (y + offY).clamp(0, h - 1);
        final si = (syp * w + sxp) * 3;
        final di = (y * w + x) * 3;
        snapshot[di] = [
          buf[di] * (1 - wt) + buf[si] * wt,
          buf[di + 1] * (1 - wt) + buf[si + 1] * wt,
          buf[di + 2] * (1 - wt) + buf[si + 2] * wt,
        ];
      }
    }
    snapshot.forEach((di, v) {
      buf[di] = v[0];
      buf[di + 1] = v[1];
      buf[di + 2] = v[2];
    });
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
