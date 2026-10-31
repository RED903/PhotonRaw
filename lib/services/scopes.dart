import 'dart:math' as math;
import 'dart:typed_data';

import 'pipeline_core.dart' show kCeqCenters;

const int kScopeW = 280;
const int kScopeH = 140;

class ScopeData {
  final Uint8List waveformRgba;
  final Uint8List paradeRgba;
  final Uint8List histogramRgba;
  final List<double> bandLevels;

  ScopeData({
    required this.waveformRgba,
    required this.paradeRgba,
    required this.histogramRgba,
    required this.bandLevels,
  });
}

/// 표시용 RGBA8 결과에서 Waveform, Parade, Histogram, 8-Band 스코프를 한 번에 계산 (원본 scopes.py 1:1 포팅)
ScopeData computeAllScopes(Uint8List rgba, int w, int h) {
  final stepX = math.max(1, w ~/ 256);
  final stepY = math.max(1, h ~/ 144);
  final sw = (w + stepX - 1) ~/ stepX;
  final sh = (h + stepY - 1) ~/ stepY;
  final sample = Float32List(sw * sh * 3);
  var si = 0;
  for (var y = 0; y < h; y += stepY) {
    for (var x = 0; x < w; x += stepX) {
      final o = (y * w + x) * 4;
      sample[si++] = rgba[o] / 255.0;
      sample[si++] = rgba[o + 1] / 255.0;
      sample[si++] = rgba[o + 2] / 255.0;
    }
  }

  final levels = _bandLevels(sample, sw, sh);

  Uint8List makeBlankCanvas() {
    final c = Uint8List(kScopeW * kScopeH * 4);
    for (var i = 0; i < kScopeW * kScopeH; i++) {
      c[i * 4] = 18;
      c[i * 4 + 1] = 18;
      c[i * 4 + 2] = 18;
      c[i * 4 + 3] = 255;
    }
    return c;
  }

  final wf = makeBlankCanvas();
  final pr = makeBlankCanvas();
  final hs = makeBlankCanvas();

  _drawWaveform(wf, sample, sw, sh);
  _drawParade(pr, sample, sw, sh);
  _drawHistogram(hs, sample, sw, sh);

  return ScopeData(
    waveformRgba: wf,
    paradeRgba: pr,
    histogramRgba: hs,
    bandLevels: levels,
  );
}

void _add(Uint8List c, int x, int y, int ch, int amt) {
  final o = (y * kScopeW + x) * 4 + ch;
  c[o] = math.min(255, c[o] + amt);
}

int _yIdx(double v) => ((1.0 - v) * (kScopeH - 1)).toInt().clamp(0, kScopeH - 1);

void _drawWaveform(Uint8List canvas, Float32List s, int sw, int sh) {
  for (var cx = 0; cx < kScopeW; cx++) {
    final sx = sw <= 1 ? 0 : (cx * (sw - 1) / (kScopeW - 1)).toInt();
    for (var y = 0; y < sh; y++) {
      final o = (y * sw + sx) * 3;
      _add(canvas, cx, _yIdx(s[o]), 0, 30);
      _add(canvas, cx, _yIdx(s[o + 1]), 1, 30);
      _add(canvas, cx, _yIdx(s[o + 2]), 2, 30);
    }
  }
}

void _drawParade(Uint8List canvas, Float32List s, int sw, int sh) {
  final subW = kScopeW ~/ 3;
  for (var cx = 0; cx < subW; cx++) {
    final sx = sw <= 1 ? 0 : (cx * (sw - 1) / (subW - 1)).toInt();
    for (var y = 0; y < sh; y++) {
      final o = (y * sw + sx) * 3;
      _add(canvas, cx, _yIdx(s[o]), 0, 45);
      _add(canvas, subW + cx, _yIdx(s[o + 1]), 1, 45);
      final bx = subW * 2 + cx;
      if (bx < kScopeW) _add(canvas, bx, _yIdx(s[o + 2]), 2, 45);
    }
  }
  for (var y = 0; y < kScopeH; y++) {
    for (final x in [subW, subW * 2]) {
      final o = (y * kScopeW + x) * 4;
      canvas[o] = 40;
      canvas[o + 1] = 40;
      canvas[o + 2] = 40;
    }
  }
}

void _drawHistogram(Uint8List canvas, Float32List s, int sw, int sh) {
  final hist = List.generate(3, (_) => List<double>.filled(kScopeW, 0.0));
  final n = sw * sh;
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < 3; c++) {
      final b = (s[i * 3 + c] * (kScopeW - 1)).toInt().clamp(0, kScopeW - 1);
      hist[c][b] += 1.0;
    }
  }
  var maxVal = 1.0;
  for (final hc in hist) {
    for (final v in hc) {
      if (v > maxVal) maxVal = v;
    }
  }
  for (var x = 0; x < kScopeW; x++) {
    for (var c = 0; c < 3; c++) {
      final hgt = (hist[c][x] / maxVal * (kScopeH - 10)).toInt();
      for (var y = kScopeH - hgt; y < kScopeH; y++) {
        final o = (y * kScopeW + x) * 4 + c;
        if (canvas[o] < 200) canvas[o] = 200;
      }
    }
  }
}

List<double> _bandLevels(Float32List s, int sw, int sh) {
  final n = sw * sh;
  final sums = List<double>.filled(8, 0.0);
  final counts = List<int>.filled(8, 0);

  for (var i = 0; i < n; i++) {
    final r = s[i * 3].toDouble();
    final g = s[i * 3 + 1].toDouble();
    final b = s[i * 3 + 2].toDouble();
    final cMax = math.max(r, math.max(g, b));
    final cMin = math.min(r, math.min(g, b));
    final delta = cMax - cMin;
    if (delta <= 1e-4) continue;
    final l = (cMax + cMin) * 0.5;
    final sat = l <= 0.5 ? delta / (cMax + cMin) : delta / (2.0 - cMax - cMin);

    double hue;
    if (cMax == r) {
      hue = ((g - b) / delta) % 6.0;
    } else if (cMax == g) {
      hue = ((b - r) / delta) + 2.0;
    } else {
      hue = ((r - g) / delta) + 4.0;
    }
    hue = (hue / 6.0) % 1.0;
    if (hue < 0) hue += 1.0;

    for (var k = 0; k < 8; k++) {
      var dist = (hue - kCeqCenters[k]).abs();
      dist = math.min(dist, 1.0 - dist);
      final wBand = math.max(0.0, 1.0 - dist / 0.12);
      if (wBand > 0.3) {
        sums[k] += sat * wBand;
        counts[k]++;
      }
    }
  }

  return [
    for (var k = 0; k < 8; k++)
      (counts[k] > 10 ? (sums[k] / counts[k]) * 1.5 : 0.02).clamp(0.02, 0.98).toDouble()
  ];
}
