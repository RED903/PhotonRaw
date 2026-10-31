import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon_raw/main.dart';
import 'package:photon_raw/models/pipeline_params.dart';
import 'package:photon_raw/services/curve_lut.dart';
import 'package:photon_raw/services/pipeline_core.dart';
import 'package:photon_raw/services/scopes.dart';

void main() {
  test('renderPreview 18개 모듈 수학 연산 및 computeAllScopes 정상 작동 검증', () {
    const w = 32;
    const h = 32;
    final src = Uint8List(w * h * 3);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = (y * w + x) * 3;
        src[idx] = (x * 8).clamp(0, 255);
        src[idx + 1] = (y * 8).clamp(0, 255);
        src[idx + 2] = 128;
      }
    }

    final params = PipelineParams()
      ..exposureEnabled = true
      ..expEv = 0.5
      ..expContrast = 0.15
      ..sigmoidEnabled = true
      ..sigContrast = 1.5
      ..toneEqualizerEnabled = true
      ..teShadows = 0.3
      ..teHighlights = -0.3
      ..toneCurveEnabled = true
      ..toneCurvePoints = {
        'rgb': [
          [0.0, 0.05],
          [0.5, 0.55],
          [1.0, 0.95],
        ],
        'r': [
          [0.0, 0.0],
          [1.0, 1.0],
        ],
        'g': [
          [0.0, 0.0],
          [1.0, 1.0],
        ],
        'b': [
          [0.0, 0.0],
          [1.0, 1.0],
        ],
      }
      ..wbEnabled = true
      ..wbTemperature = 6200.0
      ..colorZonesEnabled = true
      ..satGlobal = 0.10
      ..satVibrance = 0.20
      ..colorEqualizerEnabled = true
      ..ceqSat = [0.10, 0.0, 0.0, 0.15, 0.0, 0.20, 0.0, 0.0]
      ..colorBalanceEnabled = true
      ..cbShadowsR = -0.12
      ..cbMidtonesG = 0.05
      ..cbMidtonesB = 0.12
      ..cbHighlightsR = 0.10
      ..dehazeEnabled = true
      ..dhStrength = 0.20
      ..sharpenEnabled = true
      ..shAmount = 0.35
      ..localContrastEnabled = true
      ..lcDetail = 0.20
      ..lcClarity = 0.15
      ..denoiseEnabled = true
      ..dnStrength = 0.20
      ..vignetteEnabled = true
      ..vgAmount = -0.3;

    final out = renderPreview(ProxyImage(w, h, src), params, wantBefore: true);
    expect(out.width, w);
    expect(out.height, h);
    expect(out.rgba.length, w * h * 4);
    expect(out.beforeRgba, isNotNull);

    final scopes = computeAllScopes(out.rgba, out.width, out.height);
    expect(scopes.waveformRgba.length, kScopeW * kScopeH * 4);
    expect(scopes.paradeRgba.length, kScopeW * kScopeH * 4);
    expect(scopes.histogramRgba.length, kScopeW * kScopeH * 4);
    expect(scopes.bandLevels.length, 8);

    final lut = evaluateMonotoneCubicSpline([
      [0.0, 0.0],
      [0.5, 0.6],
      [1.0, 1.0],
    ], 256);
    expect(lut.length, 256);
    expect(lut.first, closeTo(0.0, 1e-3));
    expect(lut.last, closeTo(1.0, 1e-3));
  });

  testWidgets('PhotonRaw 초기 실행 시 물결 이미지 없이 빈 다크룸 UI 및 6개 카테고리 탭 렌더링 확인', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const PhotonRawApp());
    expect(find.text('⚡ PhotonRaw'), findsOneWidget);
    expect(find.text('사진 또는 RAW 파일을 불러오세요'), findsOneWidget);
    expect(find.text('전체'), findsOneWidget);
    expect(find.text('활성'), findsOneWidget);
    expect(find.text('톤/노출'), findsOneWidget);
    expect(find.text('색상'), findsOneWidget);
    expect(find.text('기하학'), findsOneWidget);
    expect(find.text('디테일'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
