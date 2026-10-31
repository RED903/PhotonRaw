import 'dart:math' as math;
import 'dart:typed_data';

/// 기본 직선(0,0)-(1,1)인지 확인
bool isIdentityCurve(List<List<double>> pts) {
  if (pts.length != 2) return false;
  final a = pts[0];
  final b = pts[1];
  return a[0].abs() < 1e-6 &&
      a[1].abs() < 1e-6 &&
      (b[0] - 1.0).abs() < 1e-6 &&
      (b[1] - 1.0).abs() < 1e-6;
}

/// Fritsch-Carlson Monotone Cubic Spline (SemiDarktable widgets.py 와 동일 알고리즘)
Float32List evaluateMonotoneCubicSpline(List<List<double>> points, [int numSamples = 256]) {
  final pts = [
    for (final p in points) [p[0], p[1]]
  ]..sort((a, b) => a[0].compareTo(b[0]));
  final n = pts.length;
  final lut = Float32List(numSamples);
  final denom = math.max(1, numSamples - 1);

  if (n <= 1) {
    for (var i = 0; i < numSamples; i++) {
      lut[i] = i / denom;
    }
    return lut;
  }

  if (n == 2) {
    final x0 = pts[0][0], y0 = pts[0][1];
    final x1 = pts[1][0], y1 = pts[1][1];
    final dx = math.max(1e-6, x1 - x0);
    for (var i = 0; i < numSamples; i++) {
      final xs = i / denom;
      lut[i] = (y0 + (y1 - y0) * ((xs - x0) / dx)).clamp(0.0, 1.0).toDouble();
    }
    return lut;
  }

  final x = [for (final p in pts) p[0]];
  final y = [for (final p in pts) p[1]];

  final d = List<double>.filled(n - 1, 0.0);
  for (var k = 0; k < n - 1; k++) {
    final dx = x[k + 1] - x[k];
    d[k] = dx > 1e-6 ? (y[k + 1] - y[k]) / dx : 0.0;
  }

  final m = List<double>.filled(n, 0.0);
  m[0] = d[0];
  for (var k = 1; k < n - 1; k++) {
    if (d[k - 1] * d[k] <= 0) {
      m[k] = 0.0;
    } else {
      m[k] = (d[k - 1] + d[k]) * 0.5;
    }
  }
  m[n - 1] = d[n - 2];

  for (var k = 0; k < n - 1; k++) {
    if (d[k] == 0) {
      m[k] = 0.0;
      m[k + 1] = 0.0;
    } else {
      final alpha = m[k] / d[k];
      final beta = m[k + 1] / d[k];
      final sumAb = alpha * alpha + beta * beta;
      if (sumAb > 9.0) {
        final tau = 3.0 / math.sqrt(sumAb);
        m[k] = tau * alpha * d[k];
        m[k + 1] = tau * beta * d[k];
      }
    }
  }

  for (var i = 0; i < numSamples; i++) {
    final tx = i / denom;
    var k = 0;
    for (var j = 0; j < n - 1; j++) {
      if (tx >= x[j]) k = j;
    }
    k = math.min(k, n - 2);

    final h = math.max(1e-6, x[k + 1] - x[k]);
    final t = ((tx - x[k]) / h).clamp(0.0, 1.0).toDouble();
    final t2 = t * t;
    final t3 = t2 * t;

    final h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
    final h10 = t3 - 2.0 * t2 + t;
    final h01 = -2.0 * t3 + 3.0 * t2;
    final h11 = t3 - t2;

    final val = h00 * y[k] + h10 * h * m[k] + h01 * y[k + 1] + h11 * h * m[k + 1];
    lut[i] = val.clamp(0.0, 1.0).toDouble();
  }
  return lut;
}
