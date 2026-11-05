import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photon_raw/main.dart';
import 'package:photon_raw/models/liquify_params.dart';
import 'package:photon_raw/models/pipeline_params.dart';
import 'package:photon_raw/services/liquify_service.dart';
import 'package:photon_raw/services/curve_lut.dart';
import 'package:photon_raw/services/lens_profile_service.dart';
import 'package:photon_raw/services/pipeline_core.dart';
import 'package:photon_raw/services/raw_decoder.dart';
import 'package:photon_raw/services/scopes.dart';
import 'package:photon_raw/services/xmp_service.dart';
import 'package:photon_raw/widgets/calibration_widget.dart';
import 'package:photon_raw/widgets/color_equalizer_widget.dart';
import 'package:photon_raw/widgets/color_grading_widget.dart';
import 'package:photon_raw/widgets/tone_curve_widget.dart';

void main() {
  test('비네팅 -100 강한 효과·세부 슬라이더, 그레인/디노이즈 확장 파라미터 동작 검증', () {
    const w = 120, h = 80;
    final gray = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 160);
    final proxy = ProxyImage(w, h, gray);

    int px(RenderOutput o, int x, int y) => o.rgba[(y * w + x) * 4];

    // 비네팅 -100: 모서리가 중앙 대비 확실히 어두워야 함
    final vg = PipelineParams()
      ..vignetteEnabled = true
      ..vgAmount = -1.0;
    final vgOut = renderPreview(proxy, vg);
    final center = px(vgOut, w ~/ 2, h ~/ 2);
    final corner = px(vgOut, 1, 1);
    expect(corner, lessThan(center * 0.3));

    // Midpoint를 높이면 같은 위치(가장자리 안쪽)에서 덜 어두워짐
    final vgLate = PipelineParams()
      ..vignetteEnabled = true
      ..vgAmount = -1.0
      ..vgMidpoint = 1.0;
    final lateOut = renderPreview(proxy, vgLate);
    expect(px(lateOut, w ~/ 8, h ~/ 8), greaterThan(px(vgOut, w ~/ 8, h ~/ 8)));

    // Roundness 변화 시 렌더링이 정상 동작
    final vgRect = PipelineParams()
      ..vignetteEnabled = true
      ..vgAmount = -0.6
      ..vgRoundness = -1.0;
    expect(renderPreview(proxy, vgRect).rgba.length, w * h * 4);

    // 그레인: 크기/거칠기 변경에 따라 결과가 달라지고 크래시 없음
    final grA = PipelineParams()
      ..grainEnabled = true
      ..grAmount = 0.8
      ..grSize = 0.0
      ..grRoughness = 1.0;
    final grB = PipelineParams()
      ..grainEnabled = true
      ..grAmount = 0.8
      ..grSize = 1.0
      ..grRoughness = 0.0;
    final a = renderPreview(proxy, grA).rgba;
    final b = renderPreview(proxy, grB).rgba;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) diff++;
    }
    expect(diff, greaterThan(100));

    // 디노이즈: 휘도/색 노이즈 슬라이더 동작
    final dn = PipelineParams()
      ..denoiseEnabled = true
      ..dnStrength = 0.8
      ..dnColor = 0.8
      ..dnDetail = 0.5;
    expect(renderPreview(proxy, dn).rgba.length, w * h * 4);

    // 직렬화 왕복
    final restored = PipelineParams.fromMap(vgRect.toMap());
    expect(restored.vgRoundness, closeTo(-1.0, 1e-9));
    expect(PipelineParams.fromMap(grA.toMap()).grSize, closeTo(0.0, 1e-9));
    expect(PipelineParams.fromMap(dn.toMap()).dnColor, closeTo(0.8, 1e-9));
  });
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
    expect(find.text('⚡ PhotonRaw v1.0.16'), findsOneWidget);
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

  test('스팟 리무버: 가산 백화 현상 제거 및 블랙 포인트/대비 보존 검증', () {
    const w = 40, h = 40;
    final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 100);
    // 소스 영역 중앙에 순수 블랙 픽셀 배치
    final sx = 30, sy = 20;
    rgb[(sy * w + sx) * 3] = 0;
    rgb[(sy * w + sx) * 3 + 1] = 0;
    rgb[(sy * w + sx) * 3 + 2] = 0;

    final p = PipelineParams()
      ..spotEnabled = true
      ..spots = [
        Spot(x: 10 / w, y: 20 / h, r: 0.15, srcX: sx / w, srcY: sy / h),
      ];
    final out = renderPreview(ProxyImage(w, h, rgb), p);
    // 타겟 중심(10, 20)에 소스의 블랙 픽셀이 복제되었을 때, 가산 오프셋으로 인해 허옇게 뜨지 않고 0에 가깝게 유지되어야 함
    final targetIdx = (20 * w + 10) * 4;
    expect(out.rgba[targetIdx], lessThan(5));
    expect(out.rgba[targetIdx + 1], lessThan(5));
    expect(out.rgba[targetIdx + 2], lessThan(5));
  });

  test('색 보정 (Color Grading) 3-Way 휠, 휘도, 혼합, 균형 연산 검증', () {
    const w = 20, h = 20;
    final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 128);
    final proxy = ProxyImage(w, h, rgb);

    final p = PipelineParams()
      ..colorGradingEnabled = true
      ..cgMidtonesHue = 120.0 // Green
      ..cgMidtonesSat = 80.0
      ..cgShadowsHue = 240.0 // Blue
      ..cgShadowsSat = 80.0
      ..cgHighlightsHue = 0.0 // Red
      ..cgHighlightsSat = 80.0
      ..cgBlending = 50.0
      ..cgBalance = 0.0;

    final out = renderPreview(proxy, p);
    expect(out.rgba.length, w * h * 4);
    // 중간톤(128)에서는 Green 성분이 R, B보다 확실히 커야 함
    final midIdx = ((h ~/ 2) * w + (w ~/ 2)) * 4;
    expect(out.rgba[midIdx + 1], greaterThan(out.rgba[midIdx]));
    expect(out.rgba[midIdx + 1], greaterThan(out.rgba[midIdx + 2]));

    // 직렬화 왕복 검증
    final m = p.toMap();
    final restored = PipelineParams.fromMap(m);
    expect(restored.cgMidtonesHue, equals(120.0));
    expect(restored.cgMidtonesSat, equals(80.0));
  });

  test('보정 (Calibration) 어두운 영역 틴트 및 RGB 기본 색조/채도 시프트 검증', () {
    const w = 20, h = 20;
    final rgb = Uint8List(w * h * 3);
    for (int i = 0; i < w * h * 3; i += 3) {
      rgb[i] = 200; // Red 우세 픽셀
      rgb[i + 1] = 60;
      rgb[i + 2] = 60;
    }
    final proxy = ProxyImage(w, h, rgb);

    final p = PipelineParams()
      ..calibrationEnabled = true
      ..calibRedHue = 50.0 // Red Hue 양수 시 오렌지/옐로우 쪽(Green 증가)으로 시프트
      ..calibBlueSat = 50.0
      ..calibShadowsTint = -40.0; // 그림자 그린 틴트

    final out = renderPreview(proxy, p);
    expect(out.rgba.length, w * h * 4);
    // Red Hue가 50이면 G 성분이 원본보다 증가함
    expect(out.rgba[1], greaterThan(60));

    // 직렬화 왕복 검증
    final restored = PipelineParams.fromMap(p.toMap());
    expect(restored.calibRedHue, equals(50.0));
    expect(restored.calibShadowsTint, equals(-40.0));
  });

  test('렌즈 프로필 교정 (Lens Profile Correction) 왜곡/비네팅/TCA 검증', () {
    LensProfileService.ensureInitialized();
    expect(LensProfileService.allProfiles.isNotEmpty, isTrue);
    expect(LensProfileService.allMakers.contains('Sony'), isTrue);

    const w = 40, h = 40;
    final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 100);
    final proxy = ProxyImage(w, h, rgb);

    final p = PipelineParams()
      ..lensCorrectionEnabled = true
      ..lensProfileMake = 'Sony'
      ..lensProfileModel = 'FE 24-70mm F2.8 GM (SEL2470GM)'
      ..lensDistortionScale = 100.0
      ..lensVignetteScale = 100.0
      ..lensTcaEnabled = true;

    final out = renderPreview(proxy, p);
    expect(out.rgba.length, w * h * 4);
    // 비네팅 복원으로 인해 모서리 픽셀이 중앙 픽셀(100)보다 밝아져야 함 (비네팅 역보정)
    final cornerIdx = (0 * w + 0) * 4;
    expect(out.rgba[cornerIdx], greaterThan(100));

    // 직렬화 왕복 검증
    final restored = PipelineParams.fromMap(p.toMap());
    expect(restored.lensCorrectionEnabled, isTrue);
    expect(restored.lensProfileModel, equals('FE 24-70mm F2.8 GM (SEL2470GM)'));
  });

  test('필름스트립 변형 세팅 제외 현상 설정 복사/붙여넣기 검증', () {
    final src = PipelineParams()
      ..rotate90 = 90
      ..flipH = true
      ..angle = 12.5
      ..cropEnabled = true
      ..cropRect = [0.1, 0.2, 0.5, 0.6]
      ..exposureEnabled = true
      ..expEv = 1.25
      ..wbEnabled = true
      ..wbTemperature = 7500.0
      ..colorGradingEnabled = true
      ..cgMidtonesHue = 180.0;

    final dst = PipelineParams()
      ..rotate90 = 270
      ..flipH = false
      ..angle = -5.0
      ..cropEnabled = false
      ..cropRect = [0.0, 0.0, 1.0, 1.0]
      ..expEv = 0.0;

    // 변형 제외 복사 적용
    dst.copyDevelopmentFrom(src, excludeTransform: true);

    // 1. 변형 세팅(기하학)은 덮어씌워지지 않고 대상 이미지 고유값 유지
    expect(dst.rotate90, equals(270));
    expect(dst.flipH, isFalse);
    expect(dst.angle, equals(-5.0));
    expect(dst.cropEnabled, isFalse);
    expect(dst.cropRect, equals([0.0, 0.0, 1.0, 1.0]));

    // 2. 노출/화이트밸런스/컬러그레이딩 등 현상 파라미터는 완벽 복사됨
    expect(dst.exposureEnabled, isTrue);
    expect(dst.expEv, equals(1.25));
    expect(dst.wbEnabled, isTrue);
    expect(dst.wbTemperature, equals(7500.0));
    expect(dst.colorGradingEnabled, isTrue);
    expect(dst.cgMidtonesHue, equals(180.0));
  });

  test('포토샵 CC 2018 REA 역공학 기반 픽셀 유동화 (Liquify & Face-Aware) 파이프라인 검증', () {
    const w = 64, h = 64;
    // 테스트 이미지: 중앙에 흰색 사각형 패턴
    final rgb = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = (y * w + x) * 3;
        final isCenter = (x >= 24 && x <= 40 && y >= 24 && y <= 40);
        final val = isCenter ? 255 : 30;
        rgb[idx] = val;
        rgb[idx + 1] = val;
        rgb[idx + 2] = val;
      }
    }
    final proxy = ProxyImage(w, h, rgb);

    // 1. 유동화 브러시 (Warp) 적용 검증
    final p = PipelineParams()
      ..liquifyEnabled = true
      ..liquifyTool = LiquifyToolType.warp;

    // 중앙 사각형을 오른쪽으로 밀어내는 워프 브러시 적용
    p.liquifyGrid.applyBrush(
      tool: LiquifyToolType.warp,
      normX: 0.5,
      normY: 0.5,
      normRadius: 0.25,
      normDeltaX: 0.12,
      normDeltaY: 0.0,
      pressure: 0.8,
    );
    expect(p.liquifyGrid.isEmpty, isFalse);

    // 렌더 실행
    final warpedOut = renderPreview(proxy, p);
    expect(warpedOut.rgba.length, w * h * 4);

    // 워프 적용으로 인해 오른쪽 경계 바로 바깥(x=42, 원래는 어두운 30) 픽셀로 중앙 밝은 픽셀이 밀려와 밝기가 증가해야 함
    final rightPxIdx = (32 * w + 42) * 4;
    expect(warpedOut.rgba[rightPxIdx], greaterThan(30));

    // 2. 얼굴 인식 (Face-Aware) 파라미터 및 직렬화 검증
    p.liquifyFaceParams.eyeSizeLeft = 50.0;
    p.liquifyFaceParams.smile = 30.0;
    p.liquifyFaceParams.jawline = -25.0;
    expect(p.liquifyFaceParams.isNeutral, isFalse);

    final restored = PipelineParams.fromMap(p.toMap());
    expect(restored.liquifyEnabled, isTrue);
    expect(restored.liquifyFaceParams.eyeSizeLeft, equals(50.0));
    expect(restored.liquifyFaceParams.smile, equals(30.0));
    expect(restored.liquifyFaceParams.jawline, equals(-25.0));
  });

  test('다크테이블·라이트룸 XMP 사이드카 별점 및 메타데이터 파싱/저장, LightCraft 렌즈 DB 매칭 검증', () async {
    // 1. 임시 XMP 사이드카 파일 작성 및 로드 테스트
    final tempDir = Directory.systemTemp.createTempSync('xmp_test_');
    final dummyPhoto = File('${tempDir.path}/7M401154.ARW')..writeAsBytesSync([0, 1, 2]);
    final xmpFile = File('${tempDir.path}/7M401154.xmp');
    xmpFile.writeAsStringSync('''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
    xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
    xmlns:exifEX="http://cipa.jp/exif/1.0/"
    xmlns:aux="http://ns.adobe.com/exif/1.0/aux/"
   xmp:Rating="2"
   tiff:Model="ILCE-7M4"
   exifEX:LensModel="E 28-75mm F2.8-2.8"
   aux:Lens="E 28-75mm F2.8-2.8">
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
''');

    final xmpData = await XmpService.loadXmp(dummyPhoto.path);
    expect(xmpData, isNotNull);
    expect(xmpData!.rating, equals(2));
    expect(xmpData.lensModel, equals('E 28-75mm F2.8-2.8'));
    expect(xmpData.cameraModel, equals('ILCE-7M4'));

    // 2. 별점 수정 및 XMP 저장 검증
    final saveOk = await XmpService.saveRating(photoPath: dummyPhoto.path, rating: 4);
    expect(saveOk, isTrue);
    final reloaded = await XmpService.loadXmp(dummyPhoto.path);
    expect(reloaded!.rating, equals(4));

    // 3. LightCraft / 내장 렌즈 DB에서 'E 28-75mm F2.8-2.8' 매칭 검증
    final matchedLens = LensProfileService.findBestProfile(
      cameraName: 'ILCE-7M4',
      lensModel: 'E 28-75mm F2.8-2.8',
    );
    expect(matchedLens, isNotNull);
    // 24-70이 아니라 정확히 28-75 Tamron 렌즈로 매칭되어야 함
    expect(matchedLens!.model.contains('28-75mm'), isTrue);
    expect(matchedLens.maker.toLowerCase(), contains('tamron'));

    // 임시 디렉터리 정리
    tempDir.deleteSync(recursive: true);
  });
}
