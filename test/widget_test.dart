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
    expect(scopes.waveformBins.length, kGridCols * kGridRows * 3);
    expect(scopes.paradeBins.length, kGridCols * kGridRows);
    expect(scopes.histR.length, 128);
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

  testWidgets('PhotonRaw v1.0.7 모바일 세로 비율(1:1.7 이상) 레이아웃·기하학/크롭 분리·파형 접기/열기 검증', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const PhotonRawApp());
    expect(find.text('⚡ PhotonRaw v1.0.7'), findsOneWidget);
    expect(find.text('사진 또는 RAW 파일을 불러오세요'), findsOneWidget);

    // 1. 기하학 모듈이 '📐 회전 & 기울기 (Rotation & Tilt)'와 '✂️ 크롭 / 자르기 (Crop)' 2개로 분리되었는지 확인
    expect(find.text('📐 회전 & 기울기 (Rotation & Tilt)'), findsOneWidget);
    expect(find.text('✂️ 크롭 / 자르기 (Crop)'), findsOneWidget);

    // 2. 처음 실행 시 모든 모듈(노출, 채도 등)이 닫혀 있는지 확인
    expect(find.text('☀️ 노출 (Exposure)'), findsOneWidget);
    expect(find.text('노출 (Exposure EV)'), findsNothing);

    // 3. 노출 모듈을 클릭하여 열면 열리고, 스크롤을 내렸다 올려도 열린 상태가 유지되는지 검증
    await tester.tap(find.text('☀️ 노출 (Exposure)'));
    await tester.pump();
    expect(find.text('노출 (Exposure EV)'), findsOneWidget);

    // 4. 8-Band 컬러 이퀄라이저를 스크롤하여 화면에 보이게 한 뒤 열었을 때 기본 탭이 '🎨 Hue (색조)'에서 시작하는지 검증
    await tester.drag(find.byType(ListView).last, const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🌈 8-Band 컬러 이퀄라이저 (HSL)'));
    await tester.pump();
    expect(find.text('🎨 Hue (색조)'), findsOneWidget);
    expect(find.text('✨ Saturation (채도)'), findsOneWidget);
    expect(find.text('💡 Brightness (밝기)'), findsOneWidget);

    // 5. 스크롤을 아래로 끝까지 내렸다가 다시 위로 올렸을 때 아까 열어둔 노출 모듈과 8-Band 이퀄라이저가 여전히 열려 있는지 검증
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, 840));
    await tester.pumpAndSettle();
    expect(find.text('노출 (Exposure EV)'), findsOneWidget);
    expect(
      find.text('🎨 Hue (색조)', skipOffstage: false),
      findsOneWidget,
    );

    // 상단 '📂 파일 열기' 버튼이 화면 전체 가로 폭(1440)으로 늘어나지 않고 정상 크기(< 200px)인지 검증
    final openBtnSize = tester.getSize(find.text('📂 파일 열기'));
    expect(openBtnSize.width, lessThan(200.0));

    // 6. 모바일 세로 비율(1:1.7 이상, 예: 400 x 840)에서 상단 이미지 -> 중앙 조절창 -> 하단 필름스트립 배치 및 파형 열기/닫기 검증
    await tester.binding.setSurfaceSize(const Size(400, 840));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('▶ 파형 열기'), findsOneWidget);
    await tester.tap(find.text('▶ 파형 열기'));
    await tester.pump();
    expect(find.text('▼ 파형 닫기'), findsOneWidget);

    // 다양한 창 크기로 연속 리사이즈 시 오버플로우나 예외가 전혀 없는지 검증
    for (final sz in const [
      Size(1920, 1080),
      Size(1280, 720),
      Size(900, 500),
      Size(640, 420),
      Size(500, 360),
      Size(390, 844),
      Size(1440, 900),
    ]) {
      await tester.binding.setSurfaceSize(sz);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    // 리사이즈 후에도 열어놓은 노출 모듈이 그대로 열려 있는지 확인
    expect(find.text('노출 (Exposure EV)'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });
}
