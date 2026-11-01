import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon_raw/main.dart';
import 'package:photon_raw/models/pipeline_params.dart';
import 'package:photon_raw/services/curve_lut.dart';
import 'package:photon_raw/services/pipeline_core.dart';
import 'package:photon_raw/services/raw_decoder.dart';
import 'package:photon_raw/services/scopes.dart';
import 'package:photon_raw/widgets/color_equalizer_widget.dart';
import 'package:photon_raw/widgets/tone_curve_widget.dart';

void main() {
  test('스팟 소스 탐색: 스트로크 길이를 고려해 타겟과 겹치지 않는 위치 선택 + 경계 부드러움', () {
    const w = 200, h = 150;
    // 좌->우 완만한 그라디언트 배경 + 타겟 위치에 어두운 잡티
    final rgb = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 3;
        final v = 120 + (x * 40 ~/ w);
        rgb[o] = v;
        rgb[o + 1] = v;
        rgb[o + 2] = v;
      }
    }
    for (var y = 70; y < 80; y++) {
      for (var x = 90; x < 130; x++) {
        final o = (y * w + x) * 3;
        rgb[o] = 20;
        rgb[o + 1] = 20;
        rgb[o + 2] = 20;
      }
    }
    final proxy = ProxyImage(w, h, rgb);
    final params = PipelineParams();
    // 가로로 긴 스트로크 (정규화 좌표)
    final path = <List<double>>[
      for (var i = 0; i <= 10; i++) [0.45 + i * 0.02, 0.5],
    ];
    final r = 0.04;
    final src = findBestSpotSource(proxy, params, 0.55, 0.5, r, path: path);
    final dx = (src.$1 - 0.55) * w;
    final dy = (src.$2 - 0.5) * h;
    final shift = (dx * dx + dy * dy);
    // 스트로크 반지름(r*200=8px)의 2배 이상으로 떨어져야 함
    expect(shift, greaterThan(16.0 * 16.0));
    // 선택된 소스 중심은 어두운 잡티 위가 아니어야 함
    final sx = (src.$1 * w).round();
    final sy = (src.$2 * h).round();
    expect(rgb[(sy * w + sx) * 3], greaterThan(60));
  });

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

    // 클래리티(lcClarity)가 평탄한 이미지의 전체 밝기를 왜곡하지 않는지 검증
    final flatRgb = Uint8List.fromList(List<int>.filled(w * h * 3, 128));
    final clarParams = PipelineParams()
      ..localContrastEnabled = true
      ..lcDetail = -0.3
      ..lcClarity = 0.8;
    final flatOut = renderPreview(ProxyImage(w, h, flatRgb), clarParams);
    expect(flatOut.rgba[0], closeTo(128, 2));

    // 적목 제거(Red-Eye)가 붉은 동공(R >> G, B)만 어둡게 복원하는지 검증
    final redEyeRgb = Uint8List(w * h * 3);
    for (int i = 0; i < w * h * 3; i += 3) {
      redEyeRgb[i] = 230;
      redEyeRgb[i + 1] = 30;
      redEyeRgb[i + 2] = 30;
    }
    final reParams = PipelineParams()
      ..redEyeEnabled = true
      ..redEyes = [RedEyeSpot(x: 0.5, y: 0.5, r: 0.25, strength: 0.9)];
    final reOut = renderPreview(ProxyImage(w, h, redEyeRgb), reParams);
    final centerIdx = ((h ~/ 2) * w + (w ~/ 2)) * 4;
    expect(reOut.rgba[centerIdx], lessThan(80));

    // 스마트 스팟 소스 탐색(findBestSpotSource) 동작 검증
    final bestSrc = findBestSpotSource(
      ProxyImage(w, h, src),
      PipelineParams(),
      0.5,
      0.5,
      0.04,
      variantIndex: 0,
    );
    expect(bestSrc.$1, inInclusiveRange(0.02, 0.98));
    expect(bestSrc.$2, inInclusiveRange(0.02, 0.98));

    // 스팟 리무버 브러시 스트로크(path)가 뭉개지지 않고 선택된 모양 내부를 100% 선명하게 대체하는지 검증
    final spotTestRgb = Uint8List(w * h * 3);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final o = (y * w + x) * 3;
        // 왼쪽 절반(x < 16)은 검정(10), 오른쪽 절반(x >= 16)은 밝은 흰색(240)
        final v = x < 16 ? 10 : 240;
        spotTestRgb[o] = v;
        spotTestRgb[o + 1] = v;
        spotTestRgb[o + 2] = v;
      }
    }
    final strokeSpotParams = PipelineParams()
      ..spotEnabled = true
      ..spots = [
        Spot(
          x: 0.25,
          y: 0.50,
          r: 0.12,
          srcX: 0.75,
          srcY: 0.50,
          path: [
            [0.25, 0.35],
            [0.25, 0.65],
          ],
        ),
      ];
    final spotOut = renderPreview(
      ProxyImage(w, h, spotTestRgb),
      strokeSpotParams,
    );
    final replacedPixelIdx = ((h ~/ 2) * w + (w ~/ 4)) * 4;
    // 경계 색상 매칭이 들어가므로 정확히 240은 아니지만, 원본(10)이 소스 패치로 확실히 대체되어야 함
    expect(spotOut.rgba[replacedPixelIdx], greaterThan(150));
  });

  test('14/16-bit 센서 RAW 직접 디코딩 및 8-bit 내장 JPEG 대체 로드 차단 검증', () {
    // 1. 14/16-bit 센서 데이터가 없는 가짜/손상된 .arw 파일은 절대 8비트로 불러오지 않고 즉시 예외를 던지는지 검증
    final tempDir = Directory.systemTemp.createTempSync('photon_raw_test_');
    final fakeArw = File('${tempDir.path}/fake_8bit_only.arw');
    // JPEG SOI 시그니처만 넣은 더미 바이트
    fakeArw.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46]);
    expect(
      () => decodeImageFile(fakeArw.path),
      throwsA(isA<Exception>()),
    );
    tempDir.deleteSync(recursive: true);

    // 2. 로컬에 Sony ARW 샘플이 존재하면 14-bit 센서 RAW (32-bit Float linearRgb 포함)로 정상 디코딩되는지 검증
    const sampleArwPath = r'G:\카메라\저장\50510\7M405642.ARW';
    if (File(sampleArwPath).existsSync()) {
      final decoded = decodeImageFile(sampleArwPath);
      expect(decoded.isRaw, isTrue);
      expect(decoded.bitDepth, greaterThanOrEqualTo(12));
      expect(decoded.linearRgb, isNotNull);
      expect(decoded.linearRgb!.length, decoded.width * decoded.height * 3);
      expect(decoded.note.contains('센서 RAW'), isTrue);
      expect(decoded.asShotTint, equals(0.0));

      // 모바일 순수 Dart 베이어 디코더에서도 블루 채널이 빠지지 않고(B/G >= 0.80) 색온도가 정상 역산되는지 검증
      final mobileDecoded = decodePureDartSensorForTest(sampleArwPath);
      expect(mobileDecoded, isNotNull);
      expect(mobileDecoded!.asShotTint, equals(0.0));
      expect(mobileDecoded.asShotTemp, closeTo(6000.0, 250.0));
      final mLin = mobileDecoded.linearRgb!;
      double sumG = 0, sumB = 0;
      for (int i = 0; i < mLin.length; i += 30) {
        sumG += mLin[i + 1];
        sumB += mLin[i + 2];
      }
      final bgRatio = sumB / sumG;
      expect(bgRatio, greaterThanOrEqualTo(0.80));
    }
  });

  testWidgets('PhotonRaw v1.0.8 모바일 키보드 포커스 유지·모바일 검색창 숨김·툴바 정리·프리셋 관리 삭제 검증', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const PhotonRawApp());
    expect(find.text('⚡ PhotonRaw v1.0.10'), findsOneWidget);
    expect(find.text('사진 또는 RAW 파일을 불러오세요'), findsOneWidget);

    // 0. 상단 바에서 '📋 복사', '📌 붙여넣기', '📌 전체 적용' 및 외부 프리셋 드롭다운이 제거되고 '⚙️ 프리셋 관리'와 '🌐 격자 표시'가 상단에 있는지 검증
    expect(find.text('📋 복사'), findsNothing);
    expect(find.text('📌 붙여넣기'), findsNothing);
    expect(find.text('📌 전체 적용'), findsNothing);
    expect(find.text('⚙️ 프리셋 관리'), findsOneWidget);
    expect(find.text('🌐 격자 표시'), findsOneWidget);

    // 1. '변형/복구' 탭 및 '📐 회전 & 기울기 (Rotation & Tilt)', '✂️ 크롭 / 자르기 (Crop)', '🩹 스팟 리무버 (Spot Remover)'가 있는지 확인
    expect(find.text('변형/복구'), findsOneWidget);
    expect(find.text('📐 회전 & 기울기 (Rotation & Tilt)'), findsOneWidget);
    expect(find.text('✂️ 크롭 / 자르기 (Crop)'), findsOneWidget);
    expect(find.text('🩹 스팟 리무버 (Spot Remover)'), findsOneWidget);

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

    // 6. 모바일 세로 비율(1:1.7 이상, 예: 400 x 840)에서 모듈 검색창이 숨겨지고 파형 열기/닫기가 작동하는지 검증
    await tester.binding.setSurfaceSize(const Size(400, 840));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.text('🔍 모듈 검색 (예: 노출, 커브, 화이트밸런스, 선명도...)'),
      findsNothing,
    );
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

  testWidgets('모바일 ListView 내부에서 S-커브 및 컬러 이퀄라이저 터치 반경 확대·스크롤 분리 검증', (
    WidgetTester tester,
  ) async {
    final scrollController = ScrollController();
    Map<String, List<List<double>>> curvePts = {
      'rgb': [
        [0.0, 0.0],
        [0.5, 0.5],
        [1.0, 1.0],
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
    };
    List<double> eqHue = List<double>.filled(8, 0.0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 500,
            child: StatefulBuilder(
              builder: (context, setState) {
                return ListView(
                  controller: scrollController,
                  children: [
                    ToneCurveWidget(
                      curvePoints: curvePts,
                      onChanged: (updated) =>
                          setState(() => curvePts = updated),
                    ),
                    ColorEqualizerWidget(
                      hue: eqHue,
                      sat: List<double>.filled(8, 0.0),
                      bri: List<double>.filled(8, 0.0),
                      onChanged: (h, s, b) => setState(() => eqHue = h),
                    ),
                    const SizedBox(height: 800),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    // 1. S-커브 중앙 제어점(0.5, 0.5)에서 20px 떨어진 위치를 수직 드래그했을 때:
    //    새 점이 생기지 않고(점 개수 3개 유지) 기존 점이 이동하며, ListView 스크롤(offset == 0)이 발생하지 않는지 검증
    final curveBox = tester.getRect(find.byType(ToneCurveWidget));
    // 캔버스 영역은 상단 버튼(30px) 아래에 위치하며 중앙은 (curveBox.center.dx, curveBox.top + 30 + 195/2)
    final curveCenter = Offset(
      curveBox.center.dx + 18.0, // 기존 14px 반경에서는 놓쳤던 거리(18px)
      curveBox.top + 30.0 + 97.5,
    );
    await tester.dragFrom(curveCenter, const Offset(0, -40));
    await tester.pump();
    expect(scrollController.offset, equals(0.0));
    expect(curvePts['rgb']!.length, equals(3));
    expect(curvePts['rgb']![1][1], greaterThan(0.60));

    // 2. S-커브 좌측 상단 빈 배경 영역(곡선에서 먼 곳)을 수직 드래그했을 때:
    //    점이 추가되지 않고 ListView 스크롤이 정상 작동하는지 검증
    final emptySpot = Offset(curveBox.left + 28.0, curveBox.top + 48.0);
    await tester.dragFrom(emptySpot, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(scrollController.offset, greaterThan(50.0));
    expect(curvePts['rgb']!.length, equals(3));

    // 스크롤 원위치 후 컬러 이퀄라이저 수직 드래그 검증
    scrollController.jumpTo(0.0);
    await tester.pump();

    // 3. 컬러 이퀄라이저 중앙 기준선(노드 근처)을 수직으로 드래그했을 때:
    //    ListView 스크롤에 뺏기지 않고(offset == 0) 이퀄라이저 값이 즉시 변경되는지 검증
    final eqBox = tester.getRect(find.byType(ColorEqualizerWidget));
    final eqNodePos = Offset(
      eqBox.left + eqBox.width * 0.4375, // 4번째 밴드(Green) 중심
      eqBox.top + 32.0 + 74.0, // 캔버스 중앙 Y
    );
    await tester.dragFrom(eqNodePos, const Offset(0, -45));
    await tester.pump();
    expect(scrollController.offset, equals(0.0));
    expect(eqHue[3], greaterThan(0.35));
  });
}
