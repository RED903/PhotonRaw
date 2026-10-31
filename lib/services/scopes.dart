import 'dart:math' as math;
import 'dart:typed_data';

import 'pipeline_core.dart' show kCeqCenters;

const int kScopeW = 280;
const int kScopeH = 140;
const int kGridCols = 96;
const int kGridRows = 64;

class ScopeData {
  final Uint8List waveformRgba;
  final Uint8List paradeRgba;
  final Uint8List histogramRgba;
  final List<double> bandLevels;

  /// GPU 텍스처(ui.Image) 생성/해제 없이 CustomPainter에서 직접 그리기 위한 고속 버퍼
  final Float32List histR; // 길이 128 (0~1 정규화)
  final Float32List histG; // 길이 128 (0~1 정규화)
  final Float32List histB; // 길이 128 (0~1 정규화)
  final Uint8List waveformBins; // kGridCols * kGridRows * 3 (R,G,B 밀도 0~255)
  final Uint8List paradeBins; // kGridCols * kGridRows (단일 채널 밀도 0~255)

  ScopeData({
    required this.waveformRgba,
    required this.paradeRgba,
    required this.histogramRgba,
    required this.bandLevels,
    required this.histR,
    required this.histG,
    required this.histB,
    required this.waveformBins,
    required this.paradeBins,
  });
}

/// 표시용 RGBA8 결과에서 Waveform, Parade, Histogram, 8-Band 스코프를 계산
ScopeData computeAllScopes(Uint8List rgba, int w, int h) {
  final stepX = math.max(1, w ~/ 160);
  final stepY = math.max(1, h ~/ 100);
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

  // 1. 128-bin 히스토그램 계산
  const hBins = 128;
  final hR = Float32List(hBins);
  final hG = Float32List(hBins);
  final hB = Float32List(hBins);
  final n = sw * sh;
  for (var i = 0; i < n; i++) {
    final o = i * 3;
    final br = (sample[o] * (hBins - 1)).toInt().clamp(0, hBins - 1);
    final bg = (sample[o + 1] * (hBins - 1)).toInt().clamp(0, hBins - 1);
    final bb = (sample[o + 2] * (hBins - 1)).toInt().clamp(0, hBins - 1);
    hR[br] += 1.0;
    hG[bg] += 1.0;
    hB[bb] += 1.0;
  }
  double maxH = 1.0;
  for (var i = 0; i < hBins; i++) {
    if (hR[i] > maxH) maxH = hR[i];
    if (hG[i] > maxH) maxH = hG[i];
    if (hB[i] > maxH) maxH = hB[i];
  }
  for (var i = 0; i < hBins; i++) {
    hR[i] = (hR[i] / maxH).clamp(0.0, 1.0);
    hG[i] = (hG[i] / maxH).clamp(0.0, 1.0);
    hB[i] = (hB[i] / maxH).clamp(0.0, 1.0);
  }

  // 2. Waveform 및 Parade 고속 그리드 빈 계산
  final wfBins = Uint8List(kGridCols * kGridRows * 3);
  final prBins = Uint8List(kGridCols * kGridRows);
  final subCols = kGridCols ~/ 3;
  final amt = math.max(12, 420 ~/ math.max(1, sh));

  for (var cx = 0; cx < kGridCols; cx++) {
    final sx = sw <= 1 ? 0 : (cx * (sw - 1) ~/ (kGridCols - 1));
    for (var y = 0; y < sh; y++) {
      final o = (y * sw + sx) * 3;
      final ry = ((1.0 - sample[o]) * (kGridRows - 1)).toInt().clamp(0, kGridRows - 1);
      final gy = ((1.0 - sample[o + 1]) * (kGridRows - 1)).toInt().clamp(0, kGridRows - 1);
      final by = ((1.0 - sample[o + 2]) * (kGridRows - 1)).toInt().clamp(0, kGridRows - 1);

      final idxR = (ry * kGridCols + cx) * 3;
      final idxG = (gy * kGridCols + cx) * 3 + 1;
      final idxB = (by * kGridCols + cx) * 3 + 2;
      wfBins[idxR] = math.min(255, wfBins[idxR] + amt);
      wfBins[idxG] = math.min(255, wfBins[idxG] + amt);
      wfBins[idxB] = math.min(255, wfBins[idxB] + amt);
    }
  }

  for (var cx = 0; cx < subCols; cx++) {
    final sx = sw <= 1 ? 0 : (cx * (sw - 1) ~/ math.max(1, subCols - 1));
    for (var y = 0; y < sh; y++) {
      final o = (y * sw + sx) * 3;
      final ry = ((1.0 - sample[o]) * (kGridRows - 1)).toInt().clamp(0, kGridRows - 1);
      final gy = ((1.0 - sample[o + 1]) * (kGridRows - 1)).toInt().clamp(0, kGridRows - 1);
      final by = ((1.0 - sample[o + 2]) * (kGridRows - 1)).toInt().clamp(0, kGridRows - 1);

      final pR = ry * kGridCols + cx;
      final pG = gy * kGridCols + (subCols + cx);
      final pB = by * kGridCols + (subCols * 2 + cx);
      prBins[pR] = math.min(255, prBins[pR] + amt);
      prBins[pG] = math.min(255, prBins[pG] + amt);
      prBins[pB] = math.min(255, prBins[pB] + amt);
    }
  }

  // 호환용 더미 RGBA 버퍼 (단위 테스트 호환 유지)
  final wfRgba = Uint8List(kScopeW * kScopeH * 4);
  final prRgba = Uint8List(kScopeW * kScopeH * 4);
  final hsRgba = Uint8List(kScopeW * kScopeH * 4);

  return ScopeData(
    waveformRgba: wfRgba,
    paradeRgba: prRgba,
    histogramRgba: hsRgba,
    bandLevels: levels,
    histR: hR,
    histG: hG,
    histB: hB,
    waveformBins: wfBins,
    paradeBins: prBins,
  );
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
