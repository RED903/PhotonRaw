import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'models/pipeline_params.dart';
import 'services/pipeline_core.dart';
import 'services/preset_service.dart';
import 'services/raw_decoder.dart';
import 'services/scopes.dart';
import 'widgets/color_equalizer_widget.dart';
import 'widgets/control_slider.dart';
import 'widgets/filmstrip_widget.dart';
import 'widgets/module_card.dart';
import 'widgets/scope_analyzer_widget.dart';
import 'widgets/sigmoid_graph_widget.dart';
import 'widgets/tone_curve_widget.dart';
import 'widgets/viewport_canvas.dart';

void main() {
  // 프레임워크 및 비동기 예외로 인해 앱이 강제 종료되지 않도록 글로벌 가드 설정
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
      };
      runApp(const PhotonRawApp());
    },
    (Object error, StackTrace stack) {
      debugPrint('Uncaught zone error: $error\n$stack');
    },
  );
}

class PhotonRawApp extends StatelessWidget {
  const PhotonRawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhotonRaw v1.0.10 — Pro RAW & Photo Darkroom',
      debugShowCheckedModeBanner: false,
      // Windows flutter_windows.dll(0x3c1ca) AccessibilityBridge AXTree 크래시 원천 차단을 위해 Semantics 트리 비활성화
      builder: (context, child) => ExcludeSemantics(
        excluding: true,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF181818),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE8A838),
          secondary: Color(0xFFE8A838),
          surface: Color(0xFF222222),
        ),
      ),
      home: const DarkroomScreen(),
    );
  }
}

/// 개별 로드된 사진의 상태(원본 버퍼, 고속/고화질 프록시 버퍼, 파라미터, Undo/Redo 스택, 썸네일) 보관
class LoadedPhotoState {
  final String filePath;
  final String fileName;
  final DecodedImage fullDecoded;
  final ProxyImage fastProxy; // 슬라이더 드래그 중 즉각 반응용 (560px)
  final ProxyImage qualityProxy; // 조작 완료 후 고해상도 프리뷰용 (1150px)
  PipelineParams params;
  final List<Map<String, dynamic>> undoStack = [];
  final List<Map<String, dynamic>> redoStack = [];
  ui.Image? thumbnailImage;

  LoadedPhotoState({
    required this.filePath,
    required this.fileName,
    required this.fullDecoded,
    required this.fastProxy,
    required this.qualityProxy,
    required this.params,
    this.thumbnailImage,
  });
}

/// 백그라운드 Isolate에서 파일 디코딩 + 프록시 생성 + 썸네일 생성을 한 번에 수행하기 위한 결과 패킷
class _DecodedFileBundle {
  final String filePath;
  final DecodedImage decoded;
  final ProxyImage fastProxy;
  final ProxyImage qualityProxy;
  final ProxyImage thumbProxy;

  _DecodedFileBundle({
    required this.filePath,
    required this.decoded,
    required this.fastProxy,
    required this.qualityProxy,
    required this.thumbProxy,
  });
}

/// 최상위(Top-level) 디코딩 함수 — State(this)나 BuildContext/FocusNode가 절대 클로저에 캡처되지 않도록 클래스 외부에 정의
_DecodedFileBundle _decodeFileBundleTopLevel(String filePath) {
  final decoded = decodeImageFile(filePath);
  final qualityProxy = makeProxy(
    decoded.rgb,
    decoded.width,
    decoded.height,
    2400,
    decoded.linearRgb,
  );
  final fastProxy = makeProxy(
    qualityProxy.rgb,
    qualityProxy.width,
    qualityProxy.height,
    512,
    qualityProxy.linearRgb,
  );
  final thumbProxy = makeProxy(
    fastProxy.rgb,
    fastProxy.width,
    fastProxy.height,
    180,
  );
  return _DecodedFileBundle(
    filePath: filePath,
    decoded: decoded,
    fastProxy: fastProxy,
    qualityProxy: qualityProxy,
    thumbProxy: thumbProxy,
  );
}

/// 최상위 Isolate 실행 래퍼 (클래스 외부에서 호출하여 unsendable 객체 캡처 원천 차단)
Future<_DecodedFileBundle> _runDecodeFileInIsolate(String filePath) {
  return Isolate.run<_DecodedFileBundle>(
    () => _decodeFileBundleTopLevel(filePath),
  );
}

/// 내보내기용 순수 데이터 패킷 (Isolate 간 안전한 전달 보장 — 14/16-bit 무손실 linearRgb 포함)
class _ExportIsolateJob {
  final int width;
  final int height;
  final Uint8List rgb;
  final Float32List? linearRgb;
  final Map<String, dynamic> paramsMap;
  final String format;
  final int quality;

  const _ExportIsolateJob({
    required this.width,
    required this.height,
    required this.rgb,
    this.linearRgb,
    required this.paramsMap,
    required this.format,
    required this.quality,
  });
}

/// 최상위(Top-level) 전체 해상도 렌더링 및 인코딩 함수
Uint8List _encodeExportTopLevel(_ExportIsolateJob job) {
  final fullSrc = ProxyImage(job.width, job.height, job.rgb, job.linearRgb);
  final p = PipelineParams.fromMap(job.paramsMap);
  final fullRendered = renderFull(fullSrc, p);

  if (job.format == 'tiff16') {
    final rgb16 = toRgb16(fullRendered);
    final outImg16 = img.Image.fromBytes(
      width: fullRendered.width,
      height: fullRendered.height,
      bytes: rgb16.buffer,
      numChannels: 3,
      format: img.Format.uint16,
    );
    return Uint8List.fromList(img.encodeTiff(outImg16));
  }

  final rgb8 = toRgb8(fullRendered);
  final outImg = img.Image.fromBytes(
    width: fullRendered.width,
    height: fullRendered.height,
    bytes: rgb8.buffer,
    numChannels: 3,
  );
  if (job.format == 'png') {
    return Uint8List.fromList(img.encodePng(outImg));
  } else {
    return Uint8List.fromList(img.encodeJpg(outImg, quality: job.quality));
  }
}

/// 최상위 내보내기 Isolate 실행 래퍼
Future<Uint8List> _runExportInIsolate(_ExportIsolateJob job) {
  return Isolate.run<Uint8List>(() => _encodeExportTopLevel(job));
}

class _PreviewRenderOutput {
  final Uint8List afterRgba;
  final int afterW;
  final int afterH;
  final Uint8List? beforeRgba;
  final int beforeW;
  final int beforeH;
  final ScopeData scopes;

  _PreviewRenderOutput({
    required this.afterRgba,
    required this.afterW,
    required this.afterH,
    this.beforeRgba,
    this.beforeW = 0,
    this.beforeH = 0,
    required this.scopes,
  });
}

/// 프리뷰 파이프라인 + 스코프 계산 실행 함수
_PreviewRenderOutput _computePreviewSync({
  required ProxyImage srcProxy,
  required PipelineParams params,
  required bool cropEditMode,
  required bool softProofJpeg,
  required bool needBefore,
}) {
  final effectiveParams = params.clone();
  if (cropEditMode) {
    effectiveParams.cropEnabled = false;
  }

  final rendered = renderPreview(
    srcProxy,
    effectiveParams,
    wantBefore: needBefore,
  );

  Uint8List afterRgba = rendered.rgba;
  if (softProofJpeg) {
    final tempImg = img.Image.fromBytes(
      width: rendered.width,
      height: rendered.height,
      bytes: afterRgba.buffer,
      numChannels: 4,
    );
    final jpgBytes = img.encodeJpg(tempImg, quality: 82);
    final reDecoded = img.decodeJpg(jpgBytes);
    if (reDecoded != null) {
      afterRgba = reDecoded
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.rgba);
    }
  }

  final scopes = computeAllScopes(
    afterRgba,
    rendered.width,
    rendered.height,
  );

  return _PreviewRenderOutput(
    afterRgba: afterRgba,
    afterW: rendered.width,
    afterH: rendered.height,
    beforeRgba: rendered.beforeRgba,
    beforeW: rendered.width,
    beforeH: rendered.height,
    scopes: scopes,
  );
}

class DarkroomScreen extends StatefulWidget {
  const DarkroomScreen({super.key});

  @override
  State<DarkroomScreen> createState() => _DarkroomScreenState();
}

class _DarkroomScreenState extends State<DarkroomScreen> {
  final GlobalKey<ViewportCanvasState> _viewportKey =
      GlobalKey<ViewportCanvasState>();

  final List<LoadedPhotoState> _photos = [];
  int _currentIndex = -1;

  // 현재 화면에 표시할 GPU 텍스처 및 스코프 데이터
  ui.Image? _processedUiImage;
  ui.Image? _beforeUiImage;
  ScopeData? _scopeData;

  // 렌더링 코얼레싱 및 디바운스 타이머 (OS 스레드 남발 및 창 크기 변경 크래시 원천 차단)
  bool _isRendering = false;
  bool _hasPendingRender = false;
  bool _pendingFastMode = false;
  Timer? _qualityDebounceTimer;

  bool _isLoadingFile = false;
  String _statusMessage = '준비 완료 (v1.0.10) — 사진 또는 RAW 파일을 열어주세요';

  // 우측 모듈 필터 및 검색 상태 (SemiDarktable 6개 카테고리 탭과 동일)
  String _activeCategory = 'all'; // 'all', 'active', 'tone', 'color', 'geometry', 'detail'
  String _moduleSearchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _moduleScrollController = ScrollController();

  // 각 모듈의 아코디언 열림/닫힘 상태 영구 보관 (처음에는 모두 닫혀 있고, 사용자가 열어놓은 모듈만 열려 있도록 유지)
  final Set<String> _expandedModules = {};
  // 8밴드 컬러 이퀄라이저 기본 시작 모드 ('hue': 색조, 'sat': 채도, 'bri': 밝기)
  String _ceqMode = 'hue';

  // 세로 비율(1:1.7 이상) 모바일 화면에서 파형/히스토그램 열림/닫힘 상태 (모바일에서 공간 확보를 위해 기본 닫힘)
  bool _scopeCollapsedInTallMode = true;

  // 뷰포트 인터랙션 모드 상태
  bool _showGrid = false;
  bool _cropEditMode = false;
  double? _cropAspectRatio; // null = Free
  String _cropAspectName = 'Free';
  bool _horizonMode = false;
  bool _wbPickerMode = false;
  bool _spotEditMode = false;
  double _newSpotRadius = 0.025;
  int? _selectedSpotIndex;
  DateTime? _lastSpotUndoAt;
  int _spotVariantCounter = 0;
  bool _redEyeEditMode = false;
  double _newRedEyeRadius = 0.025;
  double _newRedEyeStrength = 0.85;
  bool _softProofJpeg = false;
  bool _filmstripCollapsed = false;

  // 사용자 프리셋 및 사용자가 삭제한 기본 내장 프리셋 목록
  Map<String, Map<String, dynamic>> _userPresets = {};
  Set<String> _deletedBuiltinPresets = {};

  LoadedPhotoState? get _currentPhoto =>
      (_currentIndex >= 0 && _currentIndex < _photos.length)
          ? _photos[_currentIndex]
          : null;

  PipelineParams get _params => _currentPhoto?.params ?? PipelineParams();

  @override
  void initState() {
    super.initState();
    _loadUserPresets();
  }

  @override
  void dispose() {
    _qualityDebounceTimer?.cancel();
    _searchController.dispose();
    _moduleScrollController.dispose();
    _safeDisposeImage(_processedUiImage);
    _safeDisposeImage(_beforeUiImage);
    for (final p in _photos) {
      _safeDisposeImage(p.thumbnailImage);
    }
    super.dispose();
  }

  /// Windows GPU 래스터 스레드가 그리기를 마친 뒤 안전하게 텍스처를 해제 (즉시 dispose 시 발생하는 C++ Access Violation 방지)
  void _safeDisposeImage(ui.Image? imgHandle) {
    if (imgHandle == null) return;
    Future.delayed(const Duration(milliseconds: 2500), () {
      try {
        imgHandle.dispose();
      } catch (_) {}
    });
  }

  Future<void> _loadUserPresets() async {
    final loaded = await PresetService.loadUserPresets();
    final deletedBuiltins = await PresetService.loadDeletedBuiltinPresets();
    if (mounted) {
      setState(() {
        _userPresets = loaded;
        _deletedBuiltinPresets = deletedBuiltins;
      });
    }
  }

  /// RGBA 바이트를 Flutter GPU 텍스처(ui.Image)로 비동기 변환
  Future<ui.Image> _bytesToUiImage(Uint8List rgba, int w, int h) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      (ui.Image result) => completer.complete(result),
    );
    return completer.future;
  }

  /// 파일 선택 다이얼로그로 이미지/RAW 열기
  Future<void> _pickAndLoadFiles() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '사진 또는 RAW 파일 열기',
        type: FileType.custom,
        allowedExtensions: [
          'arw',
          'cr2',
          'cr3',
          'nef',
          'dng',
          'raf',
          'orf',
          'rw2',
          'pef',
          'srw',
          'jpg',
          'jpeg',
          'png',
          'tif',
          'tiff',
          'webp',
          'bmp',
        ],
      );
      if (files.isEmpty) return;
      final paths = files
          .map((f) => f.path)
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toList();
      if (paths.isNotEmpty) {
        await _loadFilesFromPaths(paths);
      }
    } catch (e) {
      _showSnack('파일 열기 오류: $e');
    }
  }

  /// 백그라운드 Isolate에서 안전하게 다중 파일(JPEG, ARW 등) 로드
  Future<void> _loadFilesFromPaths(List<String> paths) async {
    if (_isLoadingFile) return;
    setState(() {
      _isLoadingFile = true;
      _statusMessage = '파일 디코딩 중... (${paths.length}개)';
    });

    int firstAddedIndex = -1;
    for (final path in paths) {
      final existingIdx = _photos.indexWhere((p) => p.filePath == path);
      if (existingIdx != -1) {
        firstAddedIndex = existingIdx;
        continue;
      }

      try {
        final bundle = await _runDecodeFileInIsolate(path);

        final thumbRgba = rgbToRgba(bundle.thumbProxy);
        final thumbImg = await _bytesToUiImage(
          thumbRgba,
          bundle.thumbProxy.width,
          bundle.thumbProxy.height,
        );

        final initParams = PipelineParams()
          ..wbAsShotTemp = bundle.decoded.asShotTemp
          ..wbAsShotTint = bundle.decoded.asShotTint
          ..wbTemperature = bundle.decoded.asShotTemp
          ..wbTint = bundle.decoded.asShotTint;

        final fileName = path.split(RegExp(r'[/\\]')).last;
        final photoState = LoadedPhotoState(
          filePath: path,
          fileName: fileName,
          fullDecoded: bundle.decoded,
          fastProxy: bundle.fastProxy,
          qualityProxy: bundle.qualityProxy,
          params: initParams,
          thumbnailImage: thumbImg,
        );

        _photos.add(photoState);
        firstAddedIndex = _photos.length - 1;
      } catch (e) {
        _showSnack('파일 디코딩 실패 ($path): $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoadingFile = false;
      if (firstAddedIndex != -1) {
        _currentIndex = firstAddedIndex;
        final p = _currentPhoto!;
        _statusMessage =
            '${p.fileName} (${p.fullDecoded.width}×${p.fullDecoded.height}) • ${p.fullDecoded.camera} [${p.fullDecoded.note}]';
      } else {
        _statusMessage = '파일을 불러오지 못했습니다.';
      }
    });

    if (_currentPhoto != null) {
      _viewportKey.currentState?.resetZoom();
      _triggerRender(fast: false);
    }
  }

  /// 파이프라인 렌더링 실행
  /// - 슬라이더 조작 중(fast: true)에는 560px 고속 프록시로 즉시 렌더링하고, 조작이 멈추면 180ms 뒤 1150px 고화질 프록시로 마감
  /// - 매 프레임 Isolate.run을 남발하지 않아 Windows에서 스레드 고갈이나 크래시가 절대 발생하지 않음
  Future<void> _triggerRender({bool fast = true}) async {
    final photo = _currentPhoto;
    if (photo == null) {
      final oldAfter = _processedUiImage;
      final oldBefore = _beforeUiImage;
      setState(() {
        _processedUiImage = null;
        _beforeUiImage = null;
        _scopeData = null;
      });
      _safeDisposeImage(oldAfter);
      _safeDisposeImage(oldBefore);
      return;
    }

    if (fast) {
      _qualityDebounceTimer?.cancel();
      _qualityDebounceTimer = Timer(const Duration(milliseconds: 260), () {
        if (mounted && _currentPhoto != null) {
          _triggerRender(fast: false);
        }
      });
    }

    if (_isRendering) {
      _hasPendingRender = true;
      _pendingFastMode = fast;
      return;
    }
    _isRendering = true;

    try {
      bool useFast = fast;
      do {
        _hasPendingRender = false;
        // S-커브, 컬러 이퀄라이저, 슬라이더 UI가 먼저 즉시(0ms) 화면에 그려지도록 이벤트 루프 양보
        if (useFast) {
          await Future<void>.delayed(Duration.zero);
          if (!mounted) break;
        }
        final cur = _currentPhoto;
        if (cur == null) break;

        final targetProxy = useFast ? cur.fastProxy : cur.qualityProxy;
        final output = _computePreviewSync(
          srcProxy: targetProxy,
          params: cur.params,
          cropEditMode: _cropEditMode,
          softProofJpeg: _softProofJpeg,
          needBefore: cur.params.splitViewEnabled,
        );

        final newAfterImg = await _bytesToUiImage(
          output.afterRgba,
          output.afterW,
          output.afterH,
        );

        ui.Image? newBeforeImg;
        if (output.beforeRgba != null &&
            output.beforeW > 0 &&
            output.beforeH > 0) {
          newBeforeImg = await _bytesToUiImage(
            output.beforeRgba!,
            output.beforeW,
            output.beforeH,
          );
        }

        if (!mounted) {
          _safeDisposeImage(newAfterImg);
          _safeDisposeImage(newBeforeImg);
          break;
        }

        final prevAfter = _processedUiImage;
        final prevBefore = _beforeUiImage;
        setState(() {
          _processedUiImage = newAfterImg;
          _beforeUiImage = newBeforeImg;
          _scopeData = output.scopes;
        });
        _safeDisposeImage(prevAfter);
        _safeDisposeImage(prevBefore);

        useFast = _pendingFastMode;
      } while (_hasPendingRender && mounted);
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = '렌더링 오류: $e');
      }
    } finally {
      _isRendering = false;
    }
  }

  /// Undo 히스토리 스냅샷 기록 (슬라이더 조작 시작 시점 또는 버튼 클릭 시점)
  void _pushUndoSnapshot() {
    final photo = _currentPhoto;
    if (photo == null) return;
    photo.undoStack.add(photo.params.toMap());
    if (photo.undoStack.length > 50) {
      photo.undoStack.removeAt(0);
    }
    photo.redoStack.clear();
  }

  void _undo() {
    final photo = _currentPhoto;
    if (photo == null || photo.undoStack.isEmpty) return;
    photo.redoStack.add(photo.params.toMap());
    final prev = photo.undoStack.removeLast();
    setState(() {
      photo.params = PipelineParams.fromMap(prev);
      _statusMessage = '실행 취소 완료 (${photo.undoStack.length}단계 남음)';
    });
    _triggerRender(fast: false);
  }

  void _redo() {
    final photo = _currentPhoto;
    if (photo == null || photo.redoStack.isEmpty) return;
    photo.undoStack.add(photo.params.toMap());
    final next = photo.redoStack.removeLast();
    setState(() {
      photo.params = PipelineParams.fromMap(next);
      _statusMessage = '다시 실행 완료';
    });
    _triggerRender(fast: false);
  }

  /// 선택된 스팟(없으면 무시)을 삭제 — 스팟 편집 모드에서 Delete/Backspace 키로 호출
  void _deleteSelectedSpotByKey() {
    if (!_spotEditMode) return;
    final photo = _currentPhoto;
    final sel = _selectedSpotIndex;
    if (photo == null || sel == null || sel < 0) return;
    if (sel >= photo.params.spots.length) return;
    _deleteSpotAt(sel);
  }

  /// 지정한 인덱스의 스팟 삭제 (실행 취소 가능)
  void _deleteSpotAt(int index) {
    final photo = _currentPhoto;
    if (photo == null || index < 0 || index >= photo.params.spots.length) {
      return;
    }
    _updateParams(
      (params) {
        params.spots.removeAt(index);
        if (params.spots.isEmpty) {
          params.spotEnabled = false;
          _selectedSpotIndex = null;
        } else {
          _selectedSpotIndex = math.min(index, params.spots.length - 1);
        }
      },
      recordUndo: true,
      fast: false,
    );
  }

  /// 파라미터 업데이트 헬퍼
  void _updateParams(
    void Function(PipelineParams p) mutator, {
    bool recordUndo = false,
    bool fast = true,
  }) {
    final photo = _currentPhoto;
    if (photo == null) return;
    if (recordUndo) {
      _pushUndoSnapshot();
    }
    setState(() {
      mutator(photo.params);
    });
    _triggerRender(fast: fast);
  }

  /// 자동 노출 보정 (SemiDarktable auto_exposure 이식)
  void _autoExposure() {
    final photo = _currentPhoto;
    if (photo == null) return;
    _pushUndoSnapshot();

    final rgb = photo.fastProxy.rgb;
    double sumLum = 0.0;
    final count = rgb.length ~/ 3;
    for (int i = 0; i < rgb.length; i += 3) {
      final r = rgb[i] / 255.0;
      final g = rgb[i + 1] / 255.0;
      final b = rgb[i + 2] / 255.0;
      sumLum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }
    final avgLum = (sumLum / count).clamp(0.01, 0.99);
    const targetLum = 0.46;
    final ratio = (targetLum / avgLum).clamp(0.125, 8.0);
    final log2Ev = math.log(ratio) / math.ln2;

    setState(() {
      photo.params.exposureEnabled = true;
      photo.params.expEv = (log2Ev * 0.75).clamp(-3.0, 3.0);
      _statusMessage =
          '자동 노출 적용됨: ${photo.params.expEv.toStringAsFixed(2)} EV';
    });
    _triggerRender(fast: false);
  }

  /// Gray World 자동 화이트밸런스 (SemiDarktable auto_wb 이식)
  void _autoWhiteBalance() {
    final photo = _currentPhoto;
    if (photo == null) return;
    _pushUndoSnapshot();

    final lin = srgb8ToLinear(photo.fastProxy);
    final d = lin.data;
    double rSum = 0, gSum = 0, bSum = 0;
    int cnt = 0;
    for (int i = 0; i < d.length; i += 3) {
      final r = d[i];
      final g = d[i + 1];
      final b = d[i + 2];
      if (r > 0.02 && r < 0.92 && g > 0.02 && g < 0.92 && b > 0.02 && b < 0.92) {
        rSum += r;
        gSum += g;
        bSum += b;
        cnt++;
      }
    }
    if (cnt < 10) return;

    final wbRes = ColorMath.wbFromSample(
      rSum / cnt,
      gSum / cnt,
      bSum / cnt,
      photo.params.wbAsShotTemp,
      photo.params.wbAsShotTint,
    );

    setState(() {
      photo.params.wbEnabled = true;
      photo.params.wbTemperature = wbRes.temp.toDouble();
      _statusMessage = '자동 WB 적용됨: ${wbRes.temp}K (틴트 수동 유지)';
    });
    _triggerRender(fast: false);
  }

  /// 뷰포트 스포이드 클릭 시 해당 위치 5x5 평균 색상으로 화이트밸런스 계산
  void _handleWbSamplePicked(double normX, double normY) {
    final photo = _currentPhoto;
    if (photo == null) return;
    _pushUndoSnapshot();

    final lin = srgb8ToLinear(photo.fastProxy);
    final geo = applyGeometry(lin, photo.params);
    final cx = (normX * (geo.width - 1)).round().clamp(0, geo.width - 1);
    final cy = (normY * (geo.height - 1)).round().clamp(0, geo.height - 1);

    double rSum = 0, gSum = 0, bSum = 0;
    int cnt = 0;
    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -2; dx <= 2; dx++) {
        final x = (cx + dx).clamp(0, geo.width - 1);
        final y = (cy + dy).clamp(0, geo.height - 1);
        final idx = (y * geo.width + x) * 3;
        rSum += geo.data[idx];
        gSum += geo.data[idx + 1];
        bSum += geo.data[idx + 2];
        cnt++;
      }
    }

    final wbRes = ColorMath.wbFromSample(
      rSum / cnt,
      gSum / cnt,
      bSum / cnt,
      photo.params.wbAsShotTemp,
      photo.params.wbAsShotTint,
    );

    setState(() {
      _wbPickerMode = false;
      photo.params.wbEnabled = true;
      photo.params.wbTemperature = wbRes.temp.toDouble();
      _statusMessage = '스포이드 WB 적용됨: ${wbRes.temp}K (틴트 수동 유지)';
    });
    _triggerRender(fast: false);
  }

  /// 프리셋 선택 및 적용
  void _applyPresetByName(String name, {bool applyToAll = false}) {
    if (_photos.isEmpty) return;
    Map<String, dynamic>? presetData = _userPresets[name];
    if (presetData == null && !_deletedBuiltinPresets.contains(name)) {
      presetData = PresetService.builtinPresets[name];
    }
    if (presetData == null) return;

    if (applyToAll) {
      for (final p in _photos) {
        p.undoStack.add(p.params.toMap());
        p.params = PresetService.applyPresetMap(p.params, presetData);
      }
      setState(() {
        _statusMessage = '프리셋 "$name"을(를) 모든 사진에 일괄 적용했습니다.';
      });
    } else if (_currentPhoto != null) {
      _pushUndoSnapshot();
      setState(() {
        _currentPhoto!.params = PresetService.applyPresetMap(
          _currentPhoto!.params,
          presetData!,
        );
        _statusMessage = '프리셋 "$name" 적용 완료';
      });
    }
    _triggerRender(fast: false);
  }

  /// 프리셋 관리 다이얼로그 (기본 내장 프리셋 포함 모든 프리셋을 사용자가 삭제 가능하도록 지원)
  Future<void> _showPresetManagerDialog() async {
    final nameCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final activeBuiltins = PresetService.builtinPresets.keys.where(
              (k) => !_deletedBuiltinPresets.contains(k),
            );
            final allNames = <String>{
              ...activeBuiltins,
              ..._userPresets.keys,
            }.toList();
            return AlertDialog(
              backgroundColor: const Color(0xFF242424),
              title: const Text(
                '⚙️ 프리셋 관리자 (Preset Manager)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 440,
                height: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: nameCtrl,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: '새 사용자 프리셋 이름 입력...',
                              isDense: true,
                              filled: true,
                              fillColor: Color(0xFF1A1A1A),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final newName = nameCtrl.text.trim();
                            if (newName.isEmpty || _currentPhoto == null) return;
                            await PresetService.saveUserPreset(
                              newName,
                              _currentPhoto!.params,
                            );
                            final reloaded =
                                await PresetService.loadUserPresets();
                            setState(() => _userPresets = reloaded);
                            setDialogState(() {});
                            nameCtrl.clear();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE8A838),
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('현재 설정 저장'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '저장된 프리셋 목록:',
                      style: TextStyle(fontSize: 12, color: Color(0xFFAAAAAA)),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView.builder(
                        itemCount: allNames.length,
                        itemBuilder: (ctx, i) {
                          final pName = allNames[i];
                          final isBuiltin =
                              PresetService.builtinPresets.containsKey(pName) &&
                              !_userPresets.containsKey(pName);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1C),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isBuiltin ? pName : '⭐ $pName',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _applyPresetByName(
                                      pName,
                                      applyToAll: false,
                                    );
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text(
                                    '현재 사진 적용',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _applyPresetByName(pName, applyToAll: true);
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text(
                                    '전체 일괄 적용',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFE8A838),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '프리셋 삭제',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () async {
                                    await PresetService.deletePreset(pName);
                                    final reloaded =
                                        await PresetService.loadUserPresets();
                                    final deletedBuiltins =
                                        await PresetService
                                            .loadDeletedBuiltinPresets();
                                    setState(() {
                                      _userPresets = reloaded;
                                      _deletedBuiltinPresets = deletedBuiltins;
                                    });
                                    setDialogState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 내보내기 다이얼로그 (SemiDarktable ExportDialog 1:1 이식: JPEG, PNG, 16-bit Master TIFF, 단일/일괄 내보내기)
  Future<void> _showExportDialog() async {
    if (_currentPhoto == null) {
      _showSnack('먼저 사진을 불러오세요.');
      return;
    }

    String format = 'jpg'; // 'jpg', 'png', 'tiff16'
    int jpgQuality = 95;
    bool exportAll = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF242424),
              title: const Text(
                '💾 이미지 내보내기 (Export)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '출력 파일 포맷:',
                      style: TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: format,
                      dropdownColor: const Color(0xFF2A2A2A),
                      items: const [
                        DropdownMenuItem(
                          value: 'jpg',
                          child: Text('JPEG (.jpg) — 8-bit 표준 공유용'),
                        ),
                        DropdownMenuItem(
                          value: 'png',
                          child: Text('PNG (.png) — 무손실 압축'),
                        ),
                        DropdownMenuItem(
                          value: 'tiff16',
                          child: Text('TIFF (.tif) — 무손실 마스터 보관용'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => format = v);
                      },
                    ),
                    if (format == 'jpg') ...[
                      const SizedBox(height: 14),
                      Text(
                        'JPEG 품질: $jpgQuality%',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Slider(
                        value: jpgQuality.toDouble(),
                        min: 50,
                        max: 100,
                        divisions: 50,
                        activeColor: const Color(0xFFE8A838),
                        onChanged: (v) =>
                            setDialogState(() => jpgQuality = v.round()),
                      ),
                    ],
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '로드된 모든 사진 일괄 내보내기 (${_photos.length}장)',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: exportAll,
                      activeColor: const Color(0xFFE8A838),
                      onChanged: (v) =>
                          setDialogState(() => exportAll = v ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _performExport(
                      format: format,
                      quality: jpgQuality,
                      exportAll: exportAll,
                    );
                  },
                  icon: const Icon(Icons.save_alt, size: 16),
                  label: const Text('내보내기 실행'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8A838),
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _performExport({
    required String format,
    required int quality,
    required bool exportAll,
  }) async {
    final targets = exportAll ? _photos : [_currentPhoto!];
    setState(() => _statusMessage = '전체 해상도 렌더링 및 내보내기 진행 중...');

    try {
      for (final item in targets) {
        final paramsMap = item.params.toMap();
        final encodedBytes = await _runExportInIsolate(
          _ExportIsolateJob(
            width: item.fullDecoded.width,
            height: item.fullDecoded.height,
            rgb: item.fullDecoded.rgb,
            linearRgb: item.fullDecoded.linearRgb,
            paramsMap: paramsMap,
            format: format,
            quality: quality,
          ),
        );

        final ext = format == 'tiff16' ? 'tif' : format;
        final baseName = item.fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
        final defaultOutName = '${baseName}_edited.$ext';

        final savedUri = await FilePicker.saveFile(
          dialogTitle: '편집된 이미지 저장 ($defaultOutName)',
          fileName: defaultOutName,
          bytes: encodedBytes,
        );
        if (savedUri != null) {
          try {
            final outFile = File.fromUri(savedUri);
            if (!await outFile.exists()) {
              await outFile.writeAsBytes(encodedBytes);
            }
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() => _statusMessage = '내보내기 완료!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = '내보내기 실패: $e');
        _showSnack('내보내기 중 오류 발생: $e');
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    final cleanMsg = msg.split('\n').first;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleanMsg,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 모듈이 현재 선택된 카테고리 탭 및 검색어 필터에 부합하는지 확인
  bool _isModuleVisible({
    required String title,
    required String category,
    required bool enabled,
  }) {
    if (_moduleSearchQuery.isNotEmpty) {
      if (!title.toLowerCase().contains(_moduleSearchQuery.toLowerCase())) {
        return false;
      }
    }
    if (_activeCategory == 'all') return true;
    if (_activeCategory == 'active') return enabled;
    return _activeCategory == category;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _pickAndLoadFiles,
        // 실행 취소 / 다시 실행 (Windows·Linux: Ctrl, macOS: Cmd)
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyY, meta: true): _redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _redo,
        // 스팟 편집 중 선택된 스팟 삭제
        const SingleActivator(LogicalKeyboardKey.delete):
            _deleteSelectedSpotByKey,
        const SingleActivator(LogicalKeyboardKey.backspace):
            _deleteSelectedSpotByKey,
        const SingleActivator(LogicalKeyboardKey.keyB): () {
          if (_currentPhoto != null) {
            _updateParams(
              (p) => p.splitViewEnabled = !p.splitViewEnabled,
              fast: false,
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyG): () {
          setState(() => _showGrid = !_showGrid);
        },
      },
      child: Focus(
        // 시작 시 자동 포커스를 받아야 Ctrl+Z / Ctrl+Y 단축키가 즉시 동작함
        autofocus: true,
        child: DropTarget(
          onDragDone: (details) {
            final paths = details.files
                .map((x) => x.path)
                .where((p) => p.isNotEmpty)
                .toList();
            if (paths.isNotEmpty) {
              _loadFilesFromPaths(paths);
            }
          },
          child: Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, rootConstraints) {
                  final maxW = math.max(240.0, rootConstraints.maxWidth);
                  final maxH = math.max(320.0, rootConstraints.maxHeight);
                  // 세로 비율이 1:1.7 이상(극단적으로 세로로 긴 모바일 화면)인지 판별
                  final isTallPortrait = (maxH / maxW) >= 1.7;
                  final inspectorWidth =
                      (maxW * 0.34).clamp(240.0, 380.0).clamp(160.0, maxW * 0.52);

                  return ClipRect(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTopActionToolbar(),
                        if (isTallPortrait) ...[
                          // 세로 1:1.7 이상 모바일 레이아웃: [제일 위: 이미지] -> [그 아래: 조절 창] -> [그 아래: 필름 스트립]
                          Expanded(
                            flex: 48,
                            child: _buildCenterViewport(),
                          ),
                          Expanded(
                            flex: 52,
                            child: _buildRightInspector(isTallPortrait: true),
                          ),
                        ] else
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _buildCenterViewport()),
                                SizedBox(
                                  width: inspectorWidth,
                                  child: _buildRightInspector(
                                    isTallPortrait: false,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        FilmstripWidget(
                          items: _photos
                              .map(
                                (p) => FilmstripItemData(
                                  filePath: p.filePath,
                                  fileName: p.fileName,
                                  thumbnail: p.thumbnailImage,
                                ),
                              )
                              .toList(),
                          currentIndex: _currentIndex,
                          collapsed: _filmstripCollapsed,
                          onToggleCollapse: () => setState(
                            () => _filmstripCollapsed = !_filmstripCollapsed,
                          ),
                          onSelect: (idx) {
                            if (idx == _currentIndex) return;
                            setState(() {
                              _currentIndex = idx;
                              final p = _currentPhoto!;
                              _statusMessage =
                                  '${p.fileName} (${p.fullDecoded.width}×${p.fullDecoded.height})';
                            });
                            _triggerRender(fast: false);
                          },
                          onRemove: (idx) {
                            final removedThumb = _photos[idx].thumbnailImage;
                            setState(() {
                              _photos.removeAt(idx);
                              if (_photos.isEmpty) {
                                _currentIndex = -1;
                              } else if (_currentIndex >= _photos.length) {
                                _currentIndex = _photos.length - 1;
                              }
                            });
                            _safeDisposeImage(removedThumb);
                            _triggerRender(fast: false);
                          },
                          onAddFiles: _pickAndLoadFiles,
                        ),
                        _buildBottomStatusBar(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 상단 헤더 툴바 (복사/붙여넣기/전체적용 및 외부 프리셋 드롭다운 제거, 프리셋 관리 버튼만 유지)
  Widget _buildTopActionToolbar() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF212121),
        border: Border(bottom: BorderSide(color: Color(0xFF333333))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Text(
                '⚡ PhotonRaw v1.0.10',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE8A838),
                ),
              ),
            ),
            _toolbarButton(
              label: '📂 파일 열기',
              tooltip: 'JPEG, PNG, TIFF 및 Sony ARW / Canon CR2 / Nikon NEF 등 열기',
              primary: true,
              onTap: _pickAndLoadFiles,
            ),
            const SizedBox(width: 6),
            _toolbarButton(
              label: '💾 내보내기',
              tooltip: 'JPEG, PNG, 16-bit Master TIFF 내보내기',
              onTap: _showExportDialog,
            ),
            const SizedBox(width: 10),
            _toolbarButton(
              label: '⚙️ 프리셋 관리',
              tooltip: '프리셋 적용, 저장 및 삭제',
              onTap: _showPresetManagerDialog,
            ),
            const SizedBox(width: 10),
            _toolbarButton(
              label: '↩ 실행취소',
              tooltip: 'Ctrl+Z',
              onTap: _undo,
            ),
            const SizedBox(width: 6),
            _toolbarButton(
              label: '↪ 다시실행',
              tooltip: 'Ctrl+Y',
              onTap: _redo,
            ),
            const SizedBox(width: 6),
            _toolbarButton(
              label: '👁 전/후 비교',
              tooltip: 'Before / After 분할 비교 뷰 토글 (단축키 B)',
              active: _params.splitViewEnabled,
              onTap: () {
                if (_currentPhoto != null) {
                  _updateParams(
                    (p) => p.splitViewEnabled = !p.splitViewEnabled,
                    fast: false,
                  );
                }
              },
            ),
            const SizedBox(width: 6),
            _toolbarButton(
              label: '🌐 격자 표시',
              tooltip: '삼등분 구도 및 수평 보조 격자 표시 토글 (단축키 G)',
              active: _showGrid,
              onTap: () => setState(() => _showGrid = !_showGrid),
            ),
            const SizedBox(width: 6),
            _toolbarButton(
              label: '🎯 소프트 프루핑',
              tooltip: '8-bit sRGB / JPEG 압축 양자화 시뮬레이션 미리보기',
              active: _softProofJpeg,
              onTap: () {
                setState(() => _softProofJpeg = !_softProofJpeg);
                _triggerRender(fast: false);
              },
            ),
            const SizedBox(width: 6),
            _toolbarButton(
              label: '🔄 전체 초기화',
              tooltip: '현재 사진의 모든 보정값을 기본값으로 초기화',
              onTap: () {
                if (_currentPhoto == null) return;
                _pushUndoSnapshot();
                setState(() {
                  final asShotT = _currentPhoto!.params.wbAsShotTemp;
                  final asShotTint = _currentPhoto!.params.wbAsShotTint;
                  _currentPhoto!.params = PipelineParams()
                    ..wbAsShotTemp = asShotT
                    ..wbAsShotTint = asShotTint
                    ..wbTemperature = asShotT
                    ..wbTint = asShotTint;
                  _statusMessage = '모든 모듈이 초기화되었습니다.';
                });
                _triggerRender(fast: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// alignment: Alignment.center 대신 Row(mainAxisSize: MainAxisSize.min)을 사용하여 버튼이 자기 글자 폭만큼만 차지하도록 보장
  Widget _toolbarButton({
    required String label,
    required String tooltip,
    required VoidCallback onTap,
    bool primary = false,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: primary
                ? const Color(0xFFE8A838)
                : active
                    ? const Color(0xFF3E3524)
                    : const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: primary || active
                  ? const Color(0xFFE8A838)
                  : const Color(0xFF3E3E3E),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      primary || active ? FontWeight.bold : FontWeight.normal,
                  color: primary
                      ? const Color(0xFF141414)
                      : active
                          ? const Color(0xFFE8A838)
                          : const Color(0xFFE0E0E0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 중앙 메인 뷰포트 영역
  Widget _buildCenterViewport() {
    return Stack(
      children: [
        ViewportCanvas(
          key: _viewportKey,
          processedImage: _processedUiImage,
          beforeImage: _beforeUiImage,
          params: _params,
          showGrid: _showGrid,
          cropEditMode: _cropEditMode,
          cropAspectRatio: _cropAspectRatio,
          horizonMode: _horizonMode,
          wbPickerMode: _wbPickerMode,
          spotEditMode: _spotEditMode,
          newSpotRadius: _newSpotRadius,
          selectedSpotIndex: _selectedSpotIndex,
          onSelectedSpotChanged: (idx) {
            setState(() => _selectedSpotIndex = idx);
          },
          onResolveSmartSpotSource: (tx, ty, r, path) {
            if (_currentPhoto == null) {
              final off = (r * 2.4).clamp(0.025, 0.16);
              return (
                (tx + off <= 0.96 ? tx + off : tx - off).clamp(0.02, 0.98),
                ty.clamp(0.02, 0.98),
              );
            }
            return findBestSpotSource(
              _currentPhoto!.fastProxy,
              _params,
              tx,
              ty,
              r,
              variantIndex: 0,
              path: path,
            );
          },
          redEyeEditMode: _redEyeEditMode,
          newRedEyeRadius: _newRedEyeRadius,
          newRedEyeStrength: _newRedEyeStrength,
          onRedEyesChanged: (redEyes) {
            _pushUndoSnapshot();
            _updateParams(
              (p) {
                p.redEyeEnabled = redEyes.isNotEmpty;
                p.redEyes = redEyes;
              },
              fast: false,
            );
          },
          onOpenFileRequested: _pickAndLoadFiles,
          onSplitPositionChanged: (pos) {
            setState(() {
              _currentPhoto?.params.splitPosition = pos;
            });
          },
          onCropRectChanged: (rect) {
            setState(() {
              _currentPhoto?.params.cropRect = rect;
            });
          },
          onHorizonAngleComputed: (deg) {
            _pushUndoSnapshot();
            setState(() {
              _horizonMode = false;
              _currentPhoto?.params.angle = deg;
              _statusMessage =
                  '수평선 자동 보정 적용됨: ${deg.toStringAsFixed(2)}°';
            });
            _triggerRender(fast: false);
          },
          onWbSamplePicked: _handleWbSamplePicked,
          onSpotsChanged: (spots) {
            // 스팟 드래그 중 매 프레임 스냅샷이 쌓이지 않도록 400ms 이내 연속 변경은 하나로 묶음
            final nowT = DateTime.now();
            if (_lastSpotUndoAt == null ||
                nowT.difference(_lastSpotUndoAt!).inMilliseconds > 400) {
              _pushUndoSnapshot();
            }
            _lastSpotUndoAt = nowT;
            _updateParams(
              (p) {
                p.spotEnabled = spots.isNotEmpty;
                p.spots = spots;
                if (_selectedSpotIndex != null &&
                    _selectedSpotIndex! >= spots.length) {
                  _selectedSpotIndex = spots.isEmpty ? null : spots.length - 1;
                }
              },
              fast: false,
            );
          },
        ),
        if (_isLoadingFile)
          Container(
            color: const Color(0xAA000000),
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFFE8A838)),
                SizedBox(height: 12),
                Text(
                  'RAW / 이미지 데이터를 디코딩하는 중...',
                  style: TextStyle(fontSize: 13, color: Colors.white),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 우측(또는 세로 1:1.7 이상 모바일에서 하단) 다크룸 인스펙터 패널
  Widget _buildRightInspector({bool isTallPortrait = false}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        border: Border(
          left: isTallPortrait
              ? BorderSide.none
              : const BorderSide(color: Color(0xFF333333)),
          top: isTallPortrait
              ? const BorderSide(color: Color(0xFF333333))
              : BorderSide.none,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showScope = isTallPortrait
              ? constraints.maxHeight >= 140
              : constraints.maxHeight >= 310;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showScope)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: ScopeAnalyzerWidget(
                    scopeData: _scopeData,
                    collapsible: isTallPortrait,
                    collapsed: isTallPortrait && _scopeCollapsedInTallMode,
                    onToggleCollapse: () => setState(
                      () => _scopeCollapsedInTallMode =
                          !_scopeCollapsedInTallMode,
                    ),
                  ),
                ),
              // 모바일(Android/iOS 또는 세로 1:1.7 이상 화면)에서는 모듈 검색 창을 표시하지 않음
              if (!isTallPortrait &&
                  !Platform.isAndroid &&
                  !Platform.isIOS)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: SizedBox(
                    height: 28,
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 11.5),
                      decoration: InputDecoration(
                        hintText: '🔍 모듈 검색 (예: 노출, 커브, 화이트밸런스, 선명도...)',
                        hintStyle: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF777777),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF161616),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              const BorderSide(color: Color(0xFF333333)),
                        ),
                        suffixIcon: _moduleSearchQuery.isNotEmpty
                            ? IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.clear, size: 14),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _moduleSearchQuery = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (v) =>
                          setState(() => _moduleSearchQuery = v.trim()),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: SizedBox(
                  height: 25,
                  child: Row(
                    children: [
                      for (final tab in [
                        ('all', '전체'),
                        ('active', '활성'),
                        ('tone', '톤/노출'),
                        ('color', '색상'),
                        ('geometry', '변형/복구'),
                        ('detail', '디테일'),
                      ])
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 1.5),
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _activeCategory = tab.$1),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _activeCategory == tab.$1
                                      ? const Color(0xFFE8A838)
                                      : const Color(0xFF2B2B2B),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Center(
                                  child: Text(
                                    tab.$2,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: _activeCategory == tab.$1
                                          ? const Color(0xFF141414)
                                          : const Color(0xFFBBBBBB),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFF333333)),
              Expanded(
                child: ListView(
                  controller: _moduleScrollController,
                  padding: const EdgeInsets.all(8),
                  children: _buildAllModuleCards(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 모든 모듈 카드가 처음에는 닫혀 있고, 사용자가 열어놓은 모듈만 스크롤/리렌더링 후에도 계속 열려 있도록 상태 연동
  Widget _buildCard({
    required String title,
    required String category,
    required bool enabled,
    bool initiallyExpanded = false,
    required ValueChanged<bool> onToggleEnabled,
    required VoidCallback onReset,
    required List<Widget> children,
  }) {
    final isExpanded = _expandedModules.contains(title);
    return ModuleCard(
      key: ValueKey('module_card_$title'),
      title: title,
      category: category,
      enabled: enabled,
      expanded: isExpanded,
      onExpansionChanged: (exp) {
        setState(() {
          if (exp) {
            _expandedModules.add(title);
          } else {
            _expandedModules.remove(title);
          }
        });
      },
      onToggleEnabled: onToggleEnabled,
      onReset: onReset,
      children: children,
    );
  }

  List<Widget> _buildAllModuleCards() {
    final p = _params;
    final cards = <Widget>[];

    // 1-A. 회전 & 기울기 (Rotation & Tilt) — rotate90: 0, 90, 180, 270 / flipH / flipV / angle
    final tiltActive = p.rotate90 != 0 ||
        p.flipH ||
        p.flipV ||
        p.angle.abs() > 1e-4;
    if (_isModuleVisible(
      title: '회전 & 기울기 (Rotation & Tilt)',
      category: 'geometry',
      enabled: tiltActive,
    )) {
      cards.add(
        _buildCard(
          title: '📐 회전 & 기울기 (Rotation & Tilt)',
          category: 'geometry',
          enabled: tiltActive,
          initiallyExpanded: false,
          onToggleEnabled: (val) {
            if (!val) {
              _updateParams(
                (params) {
                  params.rotate90 = 0;
                  params.flipH = false;
                  params.flipV = false;
                  params.angle = 0.0;
                },
                recordUndo: true,
                fast: false,
              );
            }
          },
          onReset: () {
            setState(() {
              _horizonMode = false;
            });
            _updateParams(
              (params) {
                params.rotate90 = 0;
                params.flipH = false;
                params.flipV = false;
                params.angle = 0.0;
              },
              recordUndo: true,
              fast: false,
            );
          },
          children: [
            Row(
              children: [
                Expanded(
                  child: _smallBtn('↺ 90° 왼쪽', () {
                    _updateParams(
                      (params) =>
                          params.rotate90 = (params.rotate90 + 270) % 360,
                      recordUndo: true,
                      fast: false,
                    );
                  }),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _smallBtn('↻ 90° 오른쪽', () {
                    _updateParams(
                      (params) =>
                          params.rotate90 = (params.rotate90 + 90) % 360,
                      recordUndo: true,
                      fast: false,
                    );
                  }),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _smallBtn(
                    '⇄ 좌우반전',
                    () => _updateParams(
                      (params) => params.flipH = !params.flipH,
                      recordUndo: true,
                      fast: false,
                    ),
                    active: p.flipH,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _smallBtn(
                    '⇅ 상하반전',
                    () => _updateParams(
                      (params) => params.flipV = !params.flipV,
                      recordUndo: true,
                      fast: false,
                    ),
                    active: p.flipV,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ControlSlider(
              label: '미세 기울기 (Angle)',
              value: p.angle,
              min: -45.0,
              max: 45.0,
              defaultVal: 0.0,
              decimals: 2,
              suffix: '°',
              onChangeStart: _pushUndoSnapshot,
              onChanged: (v) => _updateParams((params) => params.angle = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: _smallBtn(
                _horizonMode ? '📏 수평선 그리는 중 (드래그)' : '📏 2점 수평선 그리기',
                () => setState(() {
                  _horizonMode = !_horizonMode;
                  if (_horizonMode) _cropEditMode = false;
                }),
                active: _horizonMode,
              ),
            ),
          ],
        ),
      );
    }

    // 1-B. 크롭 / 자르기 (Crop)
    if (_isModuleVisible(
      title: '크롭 / 자르기 (Crop)',
      category: 'geometry',
      enabled: p.cropEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '✂️ 크롭 / 자르기 (Crop)',
          category: 'geometry',
          enabled: p.cropEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (val) {
            _updateParams(
              (params) => params.cropEnabled = val,
              recordUndo: true,
              fast: false,
            );
          },
          onReset: () {
            setState(() {
              _cropEditMode = false;
              _cropAspectName = 'Free';
              _cropAspectRatio = null;
            });
            _updateParams(
              (params) {
                params.cropEnabled = false;
                params.cropRect = [0.0, 0.0, 1.0, 1.0];
              },
              recordUndo: true,
              fast: false,
            );
          },
          children: [
            Row(
              children: [
                Expanded(
                  child: _smallBtn(
                    _cropEditMode ? '✂️ 크롭 편집 중' : '✂️ 크롭 영역 편집',
                    () {
                      setState(() {
                        _cropEditMode = !_cropEditMode;
                        if (_cropEditMode) _horizonMode = false;
                      });
                      _triggerRender(fast: false);
                    },
                    active: _cropEditMode,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _smallBtn(
                    '✅ 크롭 확정 적용',
                    () {
                      setState(() => _cropEditMode = false);
                      _updateParams(
                        (params) => params.cropEnabled = true,
                        recordUndo: true,
                        fast: false,
                      );
                    },
                    active: p.cropEnabled && !_cropEditMode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final ar in [
                  ('Free', null),
                  ('1:1', 1.0),
                  ('3:2', 1.5),
                  ('4:3', 4.0 / 3.0),
                  ('16:9', 16.0 / 9.0),
                  ('9:16', 9.0 / 16.0),
                ])
                  InkWell(
                    onTap: () {
                      setState(() {
                        _cropAspectName = ar.$1;
                        _cropAspectRatio = ar.$2;
                        _cropEditMode = true;
                      });
                      if (ar.$2 != null && _currentPhoto != null) {
                        final imgW =
                            _currentPhoto!.fastProxy.width.toDouble();
                        final imgH =
                            _currentPhoto!.fastProxy.height.toDouble();
                        final imgAspect = imgW / imgH;
                        final targetNormRatio = ar.$2! / imgAspect;
                        double w = 0.8;
                        double h = w / targetNormRatio;
                        if (h > 0.8) {
                          h = 0.8;
                          w = h * targetNormRatio;
                        }
                        final x0 = (1.0 - w) * 0.5;
                        final y0 = (1.0 - h) * 0.5;
                        _updateParams(
                          (params) => params.cropRect = [x0, y0, w, h],
                          fast: false,
                        );
                      } else {
                        _triggerRender(fast: false);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _cropAspectName == ar.$1
                            ? const Color(0xFF3E3524)
                            : const Color(0xFF1D1D1D),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: _cropAspectName == ar.$1
                              ? const Color(0xFFE8A838)
                              : const Color(0xFF363636),
                        ),
                      ),
                      child: Text(
                        ar.$1,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: _cropAspectName == ar.$1
                              ? const Color(0xFFE8A838)
                              : const Color(0xFFBBBBBB),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    // 1-C. 스팟 리무버 (Spot Remover) — '변형/복구' 카테고리로 이동 및 라이트크래프트 방식 브러시/소스 수정 지원
    if (_isModuleVisible(
      title: '스팟 리무버 (Spot Remover 잡티 제거)',
      category: 'geometry',
      enabled: p.spotEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '🩹 스팟 리무버 (Spot Remover)',
          category: 'geometry',
          enabled: p.spotEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.spotEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () {
            setState(() {
              _spotEditMode = false;
              _selectedSpotIndex = null;
            });
            _updateParams(
              (params) {
                params.spotEnabled = false;
                params.spots = [];
              },
              recordUndo: true,
              fast: false,
            );
          },
          children: [
            _smallBtn(
              _spotEditMode
                  ? '🖌️ 스팟 브러시 편집 중 (좌클릭 칠하기 / 원 이동 / 우클릭 삭제)'
                  : '🖌️ 뷰포트에서 스팟 브러시 편집 시작',
              () => setState(() {
                _spotEditMode = !_spotEditMode;
                if (_spotEditMode) {
                  _cropEditMode = false;
                  _horizonMode = false;
                  _wbPickerMode = false;
                  _redEyeEditMode = false;
                }
              }),
              active: _spotEditMode,
            ),
            const SizedBox(height: 5),
            const Text(
              '• 빈 곳 클릭/드래그: 드래그한 궤적 모양 그대로 스팟 툴 생성 및 완전 대체\n'
              '• 주황 테두리 드래그: 타겟 위치 수정 / 파란 테두리 드래그: 덮을 소스 위치 수정\n'
              '• 마우스 휠 클릭 드래그(또는 두 손가락): 편집 중에도 화면 이동',
              style: TextStyle(
                fontSize: 10.5,
                color: Color(0xFF9E9E9E),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            ControlSlider(
              label: '브러시 크기 (Brush Size)',
              value: _newSpotRadius,
              min: 0.005,
              max: 0.10,
              defaultVal: 0.025,
              decimals: 3,
              onChanged: (v) {
                // 브러시 크기를 줄이거나 늘려도 기존에 그려진 스팟들의 크기는 절대 변하지 않고 새로 그릴 브러시 크기만 변경
                setState(() => _newSpotRadius = v);
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _smallBtn('🔄 다른 소스 위치 찾기', () {
                    if (p.spots.isEmpty || _currentPhoto == null) return;
                    final idx = (_selectedSpotIndex != null &&
                            _selectedSpotIndex! >= 0 &&
                            _selectedSpotIndex! < p.spots.length)
                        ? _selectedSpotIndex!
                        : p.spots.length - 1;
                    _spotVariantCounter++;
                    final target = p.spots[idx];
                    final nextSrc = findBestSpotSource(
                      _currentPhoto!.fastProxy,
                      p,
                      target.x,
                      target.y,
                      target.r,
                      variantIndex: _spotVariantCounter,
                      ignoreSpotIndex: idx,
                      path: target.path,
                    );
                    _updateParams(
                      (params) {
                        params.spots[idx].srcX = nextSrc.$1;
                        params.spots[idx].srcY = nextSrc.$2;
                      },
                      recordUndo: true,
                      fast: false,
                    );
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _smallBtn('🗑 선택한 스팟 삭제 (Del)', () {
                    if (p.spots.isEmpty) return;
                    final removeIdx = (_selectedSpotIndex != null &&
                            _selectedSpotIndex! >= 0 &&
                            _selectedSpotIndex! < p.spots.length)
                        ? _selectedSpotIndex!
                        : p.spots.length - 1;
                    _deleteSpotAt(removeIdx);
                  }),
                ),
              ],
            ),
            if (p.spots.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '스팟 목록 (${p.spots.length}) — 칩을 눌러 선택, ✕로 개별 삭제',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF9E9E9E)),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (int i = 0; i < p.spots.length; i++)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _selectedSpotIndex = i),
                      child: Container(
                        padding: const EdgeInsets.only(left: 8, right: 2),
                        decoration: BoxDecoration(
                          color: i == _selectedSpotIndex
                              ? const Color(0x33FFA000)
                              : const Color(0xFF2C2C2C),
                          border: Border.all(
                            color: i == _selectedSpotIndex
                                ? const Color(0xFFFFA000)
                                : const Color(0xFF444444),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${p.spots[i].path.length >= 2 ? '스트로크' : '원'} ${i + 1}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            const SizedBox(width: 2),
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _deleteSpotAt(i),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: _smallBtn('🧹 모든 스팟 초기화 (${p.spots.length})', () {
                setState(() => _selectedSpotIndex = null);
                _updateParams(
                  (params) {
                    params.spots.clear();
                    params.spotEnabled = false;
                  },
                  recordUndo: true,
                  fast: false,
                );
              }),
            ),
          ],
        ),
      );
    }

    // 2. 노출 (Exposure)
    if (_isModuleVisible(
      title: '노출 (Exposure)',
      category: 'tone',
      enabled: p.exposureEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '☀️ 노출 (Exposure)',
          category: 'tone',
          enabled: p.exposureEnabled,
          initiallyExpanded: true,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.exposureEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.exposureEnabled = false;
              params.expEv = 0.0;
              params.expBlackLevel = 0.0;
              params.expContrast = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            _smallBtn('⚡ 자동 노출 보정 (Auto Exposure)', _autoExposure),
            const SizedBox(height: 4),
            ControlSlider(
              label: '노출 (Exposure EV)',
              value: p.expEv,
              min: -5.0,
              max: 5.0,
              defaultVal: 0.0,
              decimals: 2,
              suffix: ' EV',
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.exposureEnabled = true,
              onChanged: (v) => _updateParams((params) => params.expEv = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '블랙 레벨 (Black Level)',
              value: p.expBlackLevel,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.exposureEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.expBlackLevel = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '대비 (Contrast)',
              value: p.expContrast,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.exposureEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.expContrast = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 3. 시그모이드 (Sigmoid Tone Mapping)
    if (_isModuleVisible(
      title: '시그모이드 톤 매핑 (Sigmoid)',
      category: 'tone',
      enabled: p.sigmoidEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '📈 시그모이드 톤 매핑 (Sigmoid)',
          category: 'tone',
          enabled: p.sigmoidEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.sigmoidEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.sigmoidEnabled = false;
              params.sigContrast = 1.0;
              params.sigSkew = 0.0;
              params.sigShoulder = 0.0;
              params.sigToe = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            SigmoidGraphWidget(
              contrast: p.sigContrast,
              skew: p.sigSkew,
              shoulder: p.sigShoulder,
              toe: p.sigToe,
              onDoubleTapReset: () => _updateParams(
                (params) {
                  params.sigContrast = 1.0;
                  params.sigSkew = 0.0;
                  params.sigShoulder = 0.0;
                  params.sigToe = 0.0;
                },
                recordUndo: true,
                fast: false,
              ),
            ),
            ControlSlider(
              label: '곡선 대비 (Contrast)',
              value: p.sigContrast,
              min: 0.5,
              max: 3.0,
              defaultVal: 1.0,
              decimals: 2,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.sigmoidEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.sigContrast = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '비대칭 스큐 (Skew)',
              value: p.sigSkew,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.sigmoidEnabled = true,
              onChanged: (v) => _updateParams((params) => params.sigSkew = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '하이라이트 롤오프 (Shoulder)',
              value: p.sigShoulder,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.sigmoidEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.sigShoulder = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '섀도우 리프트 (Toe)',
              value: p.sigToe,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.sigmoidEnabled = true,
              onChanged: (v) => _updateParams((params) => params.sigToe = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 4. 톤 이퀄라이저 (Tone Equalizer)
    if (_isModuleVisible(
      title: '톤 이퀄라이저 (Tone Equalizer)',
      category: 'tone',
      enabled: p.toneEqualizerEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '🎚️ 톤 이퀄라이저 (Tone Equalizer)',
          category: 'tone',
          enabled: p.toneEqualizerEnabled,
          initiallyExpanded: true,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.toneEqualizerEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.toneEqualizerEnabled = false;
              params.teBlacks = 0.0;
              params.teShadows = 0.0;
              params.teMidtones = 0.0;
              params.teHighlights = 0.0;
              params.teWhites = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: '블랙 (Blacks)',
              value: p.teBlacks,
              min: -2.0,
              max: 2.0,
              defaultVal: 0.0,
              decimals: 2,
              suffix: ' EV',
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.toneEqualizerEnabled = true,
              onChanged: (v) => _updateParams((params) => params.teBlacks = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '섀도우 (Shadows)',
              value: p.teShadows,
              min: -2.0,
              max: 2.0,
              defaultVal: 0.0,
              decimals: 2,
              suffix: ' EV',
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.toneEqualizerEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.teShadows = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '미드톤 (Midtones)',
              value: p.teMidtones,
              min: -2.0,
              max: 2.0,
              defaultVal: 0.0,
              decimals: 2,
              suffix: ' EV',
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.toneEqualizerEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.teMidtones = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '하이라이트 (Highlights)',
              value: p.teHighlights,
              min: -2.0,
              max: 2.0,
              defaultVal: 0.0,
              decimals: 2,
              suffix: ' EV',
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.toneEqualizerEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.teHighlights = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '화이트 (Whites)',
              value: p.teWhites,
              min: -2.0,
              max: 2.0,
              defaultVal: 0.0,
              decimals: 2,
              suffix: ' EV',
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.toneEqualizerEnabled = true,
              onChanged: (v) => _updateParams((params) => params.teWhites = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 5. 톤 커브 (Tone Curve)
    if (_isModuleVisible(
      title: '톤 커브 (Tone Curve)',
      category: 'tone',
      enabled: p.toneCurveEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '📐 톤 커브 (Tone Curve)',
          category: 'tone',
          enabled: p.toneCurveEnabled,
          initiallyExpanded: true,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.toneCurveEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.toneCurveEnabled = false;
              params.toneCurvePoints = {
                for (final k in kCurveKeys)
                  k: [
                    [0.0, 0.0],
                    [1.0, 1.0],
                  ],
              };
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ToneCurveWidget(
              curvePoints: p.toneCurvePoints,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.toneCurveEnabled = true,
              onChanged: (updated) => _updateParams((params) {
                params.toneCurvePoints = updated;
              }),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 6. 하이라이트 복원 (Highlight Reconstruction)
    if (_isModuleVisible(
      title: '하이라이트 복원 (Highlight Reconstruction)',
      category: 'tone',
      enabled: p.highlightEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '✨ 하이라이트 복원 (Highlight Recovery)',
          category: 'tone',
          enabled: p.highlightEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.highlightEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.highlightEnabled = false;
              params.hlRecovery = 0.0;
              params.hlCompress = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: '복원 강도 (Recovery)',
              value: p.hlRecovery,
              min: 0.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.highlightEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.hlRecovery = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '하이라이트 압축 (Compress)',
              value: p.hlCompress,
              min: 0.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.highlightEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.hlCompress = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 8. 화이트 밸런스 (White Balance)
    if (_isModuleVisible(
      title: '화이트 밸런스 (White Balance)',
      category: 'color',
      enabled: p.wbEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '🌡️ 화이트 밸런스 (White Balance)',
          category: 'color',
          enabled: p.wbEnabled,
          initiallyExpanded: true,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.wbEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.wbEnabled = false;
              params.wbTemperature = params.wbAsShotTemp;
              params.wbTint = params.wbAsShotTint;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: _smallBtn(
                    _wbPickerMode ? '💧 픽셀 클릭 대기중' : '💧 스포이드',
                    () => setState(() => _wbPickerMode = !_wbPickerMode),
                    active: _wbPickerMode,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _smallBtn('📷 촬영값', () {
                    _updateParams(
                      (params) {
                        params.wbTemperature = params.wbAsShotTemp;
                      },
                      recordUndo: true,
                      fast: false,
                    );
                  }),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _smallBtn('⚡ 자동 WB', _autoWhiteBalance),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ControlSlider(
              label: '색온도 (Temperature)',
              value: p.wbTemperature,
              min: 2000.0,
              max: 25000.0,
              defaultVal: p.wbAsShotTemp,
              decimals: 0,
              suffix: ' K',
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.wbEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.wbTemperature = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '틴트 (Tint G/M)',
              value: p.wbTint,
              min: -1.0,
              max: 1.0,
              defaultVal: p.wbAsShotTint,
              decimals: 2,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.wbEnabled = true,
              onChanged: (v) => _updateParams((params) => params.wbTint = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 9. 채도 & 바이브런스 (Saturation & Vibrance)
    if (_isModuleVisible(
      title: '채도 & 바이브런스 (Saturation & Vibrance)',
      category: 'color',
      enabled: p.colorZonesEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '🎨 채도 & 바이브런스 (Color Zones)',
          category: 'color',
          enabled: p.colorZonesEnabled,
          initiallyExpanded: true,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.colorZonesEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.colorZonesEnabled = false;
              params.satGlobal = 0.0;
              params.satVibrance = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: '전체 채도 (Global Saturation)',
              value: p.satGlobal,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.colorZonesEnabled = true,
              onChanged: (v) => _updateParams((params) => params.satGlobal = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '바이브런스 (Vibrance)',
              value: p.satVibrance,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.colorZonesEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.satVibrance = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 10. 8-Band 컬러 이퀄라이저 (Color Equalizer)
    if (_isModuleVisible(
      title: '8-Band 컬러 이퀄라이저 (Color Equalizer)',
      category: 'color',
      enabled: p.colorEqualizerEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '🌈 8-Band 컬러 이퀄라이저 (HSL)',
          category: 'color',
          enabled: p.colorEqualizerEnabled,
          initiallyExpanded: true,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.colorEqualizerEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.colorEqualizerEnabled = false;
              params.ceqHue = List<double>.filled(8, 0.0);
              params.ceqSat = List<double>.filled(8, 0.0);
              params.ceqBri = List<double>.filled(8, 0.0);
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ColorEqualizerWidget(
              hue: p.ceqHue,
              sat: p.ceqSat,
              bri: p.ceqBri,
              mode: _ceqMode,
              onModeChanged: (m) => setState(() => _ceqMode = m),
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.colorEqualizerEnabled = true,
              onChanged: (h, s, b) => _updateParams((params) {
                params.ceqHue = h;
                params.ceqSat = s;
                params.ceqBri = b;
              }),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 11. 컬러 밸런스 RGB (Color Balance RGB — SemiDarktable 4축과 1:1 대응)
    if (_isModuleVisible(
      title: '컬러 밸런스 RGB (3-Way Color Balance)',
      category: 'color',
      enabled: p.colorBalanceEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '⚖️ 컬러 밸런스 RGB (3-Way Grading)',
          category: 'color',
          enabled: p.colorBalanceEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.colorBalanceEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.colorBalanceEnabled = false;
              params.cbShadowsR = 0.0;
              params.cbMidtonesG = 0.0;
              params.cbMidtonesB = 0.0;
              params.cbHighlightsR = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: '섀도우 시안 ↔ 레드 (Shadows C/R)',
              value: p.cbShadowsR,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.colorBalanceEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.cbShadowsR = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '미드톤 마젠타 ↔ 그린 (Midtones M/G)',
              value: p.cbMidtonesG,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.colorBalanceEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.cbMidtonesG = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '미드톤 옐로우 ↔ 블루 (Midtones Y/B)',
              value: p.cbMidtonesB,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.colorBalanceEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.cbMidtonesB = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '하이라이트 시안 ↔ 레드 (Highlights C/R)',
              value: p.cbHighlightsR,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.colorBalanceEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.cbHighlightsR = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 12. 선명도 (Sharpen)
    if (_isModuleVisible(
      title: '선명도 (Sharpen)',
      category: 'detail',
      enabled: p.sharpenEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '🔪 선명도 (Sharpen)',
          category: 'detail',
          enabled: p.sharpenEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.sharpenEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.sharpenEnabled = false;
              params.shAmount = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: '샤프닝 양 (Amount)',
              value: p.shAmount,
              min: 0.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.sharpenEnabled = true,
              onChanged: (v) => _updateParams((params) => params.shAmount = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 13. 텍스처 & 클래리티 & 디헤이즈 (Texture / Clarity / Dehaze 통합 모듈)
    final effectPanelEnabled = p.localContrastEnabled || p.dehazeEnabled;
    if (_isModuleVisible(
      title: '텍스처 & 클래리티 & 디헤이즈 (Texture Clarity Dehaze 안개 제거)',
      category: 'detail',
      enabled: effectPanelEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '✨ 텍스처 & 클래리티 & 디헤이즈',
          category: 'detail',
          enabled: effectPanelEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) {
              params.localContrastEnabled = v;
              params.dehazeEnabled = v;
            },
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.localContrastEnabled = false;
              params.dehazeEnabled = false;
              params.lcDetail = 0.0;
              params.lcClarity = 0.0;
              params.dhStrength = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: 'Texture (텍스처)',
              value: p.lcDetail,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 0,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.localContrastEnabled = true,
              onChanged: (v) => _updateParams((params) => params.lcDetail = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: 'Clarity (클래리티)',
              value: p.lcClarity,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 0,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.localContrastEnabled = true,
              onChanged: (v) => _updateParams((params) => params.lcClarity = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: 'Dehaze (안개 제거)',
              value: p.dhStrength,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 0,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.dehazeEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.dhStrength = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 14. 노이즈 감소 (Denoise)
    if (_isModuleVisible(
      title: '노이즈 감소 (Denoise)',
      category: 'detail',
      enabled: p.denoiseEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '🧹 노이즈 감소 (Denoise)',
          category: 'detail',
          enabled: p.denoiseEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.denoiseEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.denoiseEnabled = false;
              params.dnStrength = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: '노이즈 억제 강도 (Strength)',
              value: p.dnStrength,
              min: 0.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.denoiseEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.dnStrength = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 15. 색수차 제거 (Defringe)
    if (_isModuleVisible(
      title: '색수차 제거 (Defringe)',
      category: 'detail',
      enabled: p.defringeEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '🔮 색수차 제거 (Defringe)',
          category: 'detail',
          enabled: p.defringeEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.defringeEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.defringeEnabled = false;
              params.dfStrength = 0.0;
              params.dfThreshold = 0.10;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: '제거 강도 (Strength)',
              value: p.dfStrength,
              min: 0.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.defringeEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.dfStrength = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            ControlSlider(
              label: '엣지 임계값 (Threshold)',
              value: p.dfThreshold,
              min: 0.0,
              max: 50.0,
              defaultVal: 10.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.defringeEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.dfThreshold = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 16. 적목 제거 (Red Eye Correction) — 디테일 카테고리
    if (_isModuleVisible(
      title: '적목 제거 (Red Eye)',
      category: 'detail',
      enabled: p.redEyeEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '👁️ 적목 제거 (Red Eye)',
          category: 'detail',
          enabled: p.redEyeEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.redEyeEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () {
            setState(() => _redEyeEditMode = false);
            _updateParams(
              (params) {
                params.redEyeEnabled = false;
                params.redEyes = [];
              },
              recordUndo: true,
              fast: false,
            );
          },
          children: [
            _smallBtn(
              _redEyeEditMode
                  ? '👁️ 적목 브러시 편집 중 (눈동자 클릭/드래그, 우클릭: 삭제)'
                  : '👁️ 뷰포트에서 적목 브러시 편집 시작',
              () => setState(() {
                _redEyeEditMode = !_redEyeEditMode;
                if (_redEyeEditMode) {
                  _spotEditMode = false;
                  _cropEditMode = false;
                  _horizonMode = false;
                  _wbPickerMode = false;
                }
              }),
              active: _redEyeEditMode,
            ),
            const SizedBox(height: 6),
            ControlSlider(
              label: '브러시 크기 (Eye Radius)',
              value: _newRedEyeRadius,
              min: 0.005,
              max: 0.08,
              defaultVal: 0.025,
              decimals: 3,
              onChanged: (v) {
                setState(() => _newRedEyeRadius = v);
              },
            ),
            ControlSlider(
              label: '적목 억제 강도 (Strength)',
              value: _newRedEyeStrength,
              min: 10.0,
              max: 100.0,
              defaultVal: 85.0,
              scale: 0.01,
              decimals: 0,
              suffix: '%',
              onChanged: (v) {
                setState(() => _newRedEyeStrength = v);
                if (p.redEyes.isNotEmpty) {
                  _updateParams((params) {
                    for (final re in params.redEyes) {
                      re.strength = v;
                    }
                  });
                }
              },
              onChangeEnd: () => _triggerRender(fast: false),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _smallBtn('마지막 적목 삭제', () {
                    if (p.redEyes.isEmpty) return;
                    _updateParams(
                      (params) {
                        params.redEyes.removeLast();
                        if (params.redEyes.isEmpty) {
                          params.redEyeEnabled = false;
                        }
                      },
                      recordUndo: true,
                      fast: false,
                    );
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _smallBtn('모든 적목 초기화 (${p.redEyes.length})', () {
                    _updateParams(
                      (params) {
                        params.redEyes.clear();
                        params.redEyeEnabled = false;
                      },
                      recordUndo: true,
                      fast: false,
                    );
                  }),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 17. 블러 (Blur)
    if (_isModuleVisible(
      title: '블러 (Blur)',
      category: 'detail',
      enabled: p.blurEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '💧 블러 (Blur)',
          category: 'detail',
          enabled: p.blurEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.blurEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.blurEnabled = false;
              params.blurRadius = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: '블러 반경 (Radius)',
              value: p.blurRadius,
              min: 0.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.blurEnabled = true,
              onChanged: (v) =>
                  _updateParams((params) => params.blurRadius = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 18. 필름 그레인 (Film Grain)
    if (_isModuleVisible(
      title: '필름 그레인 (Film Grain)',
      category: 'detail',
      enabled: p.grainEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '🎞️ 필름 그레인 (Film Grain)',
          category: 'detail',
          enabled: p.grainEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.grainEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.grainEnabled = false;
              params.grAmount = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: '입자 강도 (Amount)',
              value: p.grAmount,
              min: 0.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.grainEnabled = true,
              onChanged: (v) => _updateParams((params) => params.grAmount = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    // 19. 비네팅 (Vignette)
    if (_isModuleVisible(
      title: '비네팅 (Vignette)',
      category: 'detail',
      enabled: p.vignetteEnabled,
    )) {
      cards.add(
        _buildCard(
          title: '⭕ 비네팅 (Vignette)',
          category: 'detail',
          enabled: p.vignetteEnabled,
          initiallyExpanded: false,
          onToggleEnabled: (v) => _updateParams(
            (params) => params.vignetteEnabled = v,
            recordUndo: true,
            fast: false,
          ),
          onReset: () => _updateParams(
            (params) {
              params.vignetteEnabled = false;
              params.vgAmount = 0.0;
            },
            recordUndo: true,
            fast: false,
          ),
          children: [
            ControlSlider(
              label: '비네팅 양 (어둡게 - ↔ + 밝게)',
              value: p.vgAmount,
              min: -100.0,
              max: 100.0,
              defaultVal: 0.0,
              scale: 0.01,
              decimals: 1,
              onChangeStart: _pushUndoSnapshot,
              onAutoTurnOn: () => p.vignetteEnabled = true,
              onChanged: (v) => _updateParams((params) => params.vgAmount = v),
              onChangeEnd: () => _triggerRender(fast: false),
            ),
          ],
        ),
      );
    }

    if (cards.isEmpty) {
      cards.add(
        const Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(
            child: Text(
              '조건에 맞는 모듈이 없습니다.',
              style: TextStyle(fontSize: 12, color: Color(0xFF777777)),
            ),
          ),
        ),
      );
    }

    return cards;
  }

  Widget _smallBtn(
    String text,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3E3524) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? const Color(0xFFE8A838) : const Color(0xFF3A3A3A),
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? const Color(0xFFE8A838) : const Color(0xFFCCCCCC),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        border: Border(top: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              _statusMessage,
              style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_softProofJpeg)
            const Text(
              '🎯 8-bit JPEG 소프트 프루핑 활성',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFFE8A838),
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}
