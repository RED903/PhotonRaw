import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'models/pipeline_params.dart';
import 'services/pipeline_engine.dart';
import 'services/preset_service.dart';
import 'services/raw_decoder.dart';
import 'widgets/color_equalizer_widget.dart';
import 'widgets/control_slider.dart';
import 'widgets/filmstrip_widget.dart';
import 'widgets/scope_analyzer_widget.dart';
import 'widgets/tone_curve_widget.dart';
import 'widgets/viewport_canvas.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PhotonRawApp());
}

class PhotonRawApp extends StatelessWidget {
  const PhotonRawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhotonRaw - Pro 14/16-bit RAW Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF181818),
          elevation: 0,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFDCA353),
          secondary: Color(0xFF64B5F6),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const MainStudioScreen(),
    );
  }
}

class MainStudioScreen extends StatefulWidget {
  const MainStudioScreen({super.key});

  @override
  State<MainStudioScreen> createState() => _MainStudioScreenState();
}

class _MainStudioScreenState extends State<MainStudioScreen> {
  // 열린 다중 사진 큐 (필름스트립)
  final List<RawImageResult> _loadedImages = [];
  final List<PipelineParams> _imageParams = [];
  int _currentImgIdx = -1;

  img.Image? _processedPreview;
  ScopeAnalysisResult? _scopeData;

  PipelineParams _params = PipelineParams();
  final TransformationController _transformController = TransformationController();

  // Undo / Redo 스택
  final List<PipelineParams> _undoStack = [];
  final List<PipelineParams> _redoStack = [];

  bool _isProcessing = false;
  bool _showBeforeAfter = false;
  bool _showGrid = false; // 3분할 9칸 점선 구도선 가이드라인 (단축키 G)
  bool _isFilmstripExpanded = true;
  bool _isDragging = false;
  String _curveChannel = 'RGB';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadSampleScene();
  }

  void _loadSampleScene() {
    final sample = _createSampleScene();
    _loadedImages.add(sample);
    _imageParams.add(PipelineParams());
    _currentImgIdx = 0;
    _params = _imageParams[0];
    _triggerPipeline(immediate: true);
  }

  /// 파일 열기 대화상자 (다중 파일 지원)
  Future<void> _openFileDialog() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'arw', 'cr2', 'cr3', 'nef', 'dng', 'raf', 'orf', 'rw2', // RAW
          'jpg', 'jpeg', 'png', 'tiff', 'tif', 'webp', 'bmp'      // 표준 이미지
        ],
      );

      if (result.isEmpty) return;

      setState(() => _isProcessing = true);
      for (final file in result) {
        if (file.path != null) {
          final loaded = await RawDecoder.loadFromFile(file.path!);
          _loadedImages.add(loaded);
          _imageParams.add(PipelineParams());
        }
      }

      if (_currentImgIdx == -1 && _loadedImages.isNotEmpty) {
        _currentImgIdx = 0;
        _params = _imageParams[0];
      } else {
        _currentImgIdx = _loadedImages.length - 1;
        _params = _imageParams[_currentImgIdx];
      }

      _triggerPipeline(immediate: true);
    } catch (e) {
      _showError('파일 열기 실패: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// 드래그 앤 드롭 파일 로드
  Future<void> _handleDroppedFiles(List<String> paths) async {
    setState(() => _isProcessing = true);
    try {
      for (final p in paths) {
        final loaded = await RawDecoder.loadFromFile(p);
        _loadedImages.add(loaded);
        _imageParams.add(PipelineParams());
      }
      _currentImgIdx = _loadedImages.length - 1;
      _params = _imageParams[_currentImgIdx];
      _triggerPipeline(immediate: true);
    } catch (e) {
      _showError('파일 로드 실패: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red[800], content: Text(msg)),
    );
  }

  void _switchImage(int idx) {
    if (idx < 0 || idx >= _loadedImages.length) return;
    setState(() {
      _currentImgIdx = idx;
      _params = _imageParams[idx];
      _undoStack.clear();
      _redoStack.clear();
    });
    _triggerPipeline(immediate: true);
  }

  void _closeImage(int idx) {
    setState(() {
      _loadedImages.removeAt(idx);
      _imageParams.removeAt(idx);
      if (_loadedImages.isEmpty) {
        _currentImgIdx = -1;
        _processedPreview = null;
        _scopeData = null;
      } else {
        _currentImgIdx = math.min(_currentImgIdx, _loadedImages.length - 1);
        _params = _imageParams[_currentImgIdx];
        _triggerPipeline(immediate: true);
      }
    });
  }

  /// Undo / Redo
  void _pushUndo() {
    _undoStack.add(_params.clone());
    _redoStack.clear();
    if (_undoStack.length > 30) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_params.clone());
    setState(() {
      _params = _undoStack.removeLast();
      if (_currentImgIdx >= 0) _imageParams[_currentImgIdx] = _params;
    });
    _triggerPipeline(immediate: true);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_params.clone());
    setState(() {
      _params = _redoStack.removeLast();
      if (_currentImgIdx >= 0) _imageParams[_currentImgIdx] = _params;
    });
    _triggerPipeline(immediate: true);
  }

  /// 파라미터 업데이트
  void _updateParams(void Function(PipelineParams p) update) {
    _pushUndo();
    setState(() {
      update(_params);
      if (_currentImgIdx >= 0) _imageParams[_currentImgIdx] = _params;
    });
    _triggerPipeline(immediate: false);
  }

  void _triggerPipeline({bool immediate = false}) {
    if (_currentImgIdx < 0 || _currentImgIdx >= _loadedImages.length) return;

    _debounceTimer?.cancel();
    if (immediate) {
      _runPipeline();
    } else {
      _debounceTimer = Timer(const Duration(milliseconds: 16), _runPipeline);
    }
  }

  void _runPipeline() {
    if (_currentImgIdx < 0 || _currentImgIdx >= _loadedImages.length) return;
    final cur = _loadedImages[_currentImgIdx];

    final result = PipelineEngine.process(
      sourceImage: cur.previewImage,
      params: _params,
    );
    setState(() {
      _processedPreview = result.image;
      _scopeData = result.scopeData;
    });
  }

  /// 이미지 내보내기 (Export)
  Future<void> _exportImage(String format) async {
    if (_currentImgIdx < 0 || _currentImgIdx >= _loadedImages.length) return;
    final cur = _loadedImages[_currentImgIdx];

    setState(() => _isProcessing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('마스터 16/32-bit Float 렌더링 중 ($format)...')),
    );

    await Future.delayed(const Duration(milliseconds: 50));
    final fullResult = PipelineEngine.process(
      sourceImage: cur.rawImage,
      params: _params,
    );

    Uint8List encoded;
    String mimeType = 'image/jpeg';
    if (format == 'png') {
      encoded = Uint8List.fromList(img.encodePng(fullResult.image));
      mimeType = 'image/png';
    } else if (format == 'tiff') {
      encoded = Uint8List.fromList(img.encodeTiff(fullResult.image));
      mimeType = 'image/tiff';
    } else {
      encoded = Uint8List.fromList(img.encodeJpg(fullResult.image, quality: 96));
      mimeType = 'image/jpeg';
    }

    final saveUri = await FilePicker.saveFile(
      dialogTitle: '보정된 이미지 내보내기',
      fileName: 'PhotonRaw_${cur.filename.replaceAll(RegExp(r'\.[^.]+$'), '')}.$format',
      bytes: encoded,
      mimeType: mimeType,
    );

    setState(() => _isProcessing = false);
    if (!mounted) return;

    if (saveUri != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.green[800], content: Text('저장 완료: $saveUri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final curImage = (_currentImgIdx >= 0 && _currentImgIdx < _loadedImages.length)
        ? _loadedImages[_currentImgIdx]
        : null;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) async {
        setState(() => _isDragging = false);
        if (details.files.isNotEmpty) {
          final paths = details.files.map((f) => f.path).toList();
          await _handleDroppedFiles(paths);
        }
      },
      child: Scaffold(
        appBar: _buildHeader(curImage),
        body: Stack(
          children: [
            Row(
              children: [
                // 1. 메인 워크스페이스 (뷰포트 + 하단 필름스트립)
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            ViewportCanvas(
                              processedImage: _processedPreview,
                              originalImage: curImage?.previewImage,
                              showBeforeAfter: _showBeforeAfter,
                              transformController: _transformController,
                            ),
                            // 3분할 9칸 점선 구도선 가이드라인
                            if (_showGrid)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(painter: _GridPainter()),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // 하단 큐 & 필름스트립
                      FilmstripWidget(
                        images: _loadedImages,
                        currentIndex: _currentImgIdx,
                        onSelect: _switchImage,
                        onClose: _closeImage,
                        isExpanded: _isFilmstripExpanded,
                        onToggle: () => setState(() => _isFilmstripExpanded = !_isFilmstripExpanded),
                      ),

                      // 하단 상태바
                      _buildStatusBar(curImage),
                    ],
                  ),
                ),

                // 2. 우측 사이드바 (360px 완전 고정)
                Container(
                  width: 360,
                  decoration: const BoxDecoration(
                    color: Color(0xFF181818),
                    border: Border(left: BorderSide(color: Color(0xFF282828))),
                  ),
                  child: Column(
                    children: [
                      // 4대 스코프 분석기 (히스토그램, 웨이브폼, 파레이드, 8밴드)
                      ScopeAnalyzerWidget(scopeData: _scopeData),
                      const Divider(height: 1, color: Color(0xFF282828)),

                      // 세부 편집 모듈들
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            _buildExposureModule(),
                            _buildWhiteBalanceModule(),
                            _buildToneCurveModule(),
                            _buildToneEqualizerModule(),
                            _buildSigmoidModule(),
                            _buildColorEqualizerModule(),
                            _buildColorZonesModule(),
                            _buildDetailEffectsModule(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 드래그 앤 드롭 오버레이
            if (_isDragging)
              Container(
                color: Colors.black.withOpacity(0.8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDCA353), width: 2),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_download, size: 64, color: Color(0xFFDCA353)),
                        SizedBox(height: 16),
                        Text(
                          'Sony ARW / Canon RAW / 이미지를 여기에 놓으세요',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildHeader(RawImageResult? curImage) {
    return AppBar(
      titleSpacing: 12,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('SemiDarktable', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF332512),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0xFF754F15)),
            ),
            child: const Text('PRO RAW GPU', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFDCA353))),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: _openFileDialog,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('사진 열기'),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
        ),
        IconButton(
          tooltip: '실행 취소 (Undo)',
          icon: const Icon(Icons.undo, size: 18),
          onPressed: _undoStack.isNotEmpty ? _undo : null,
        ),
        IconButton(
          tooltip: '다시 실행 (Redo)',
          icon: const Icon(Icons.redo, size: 18),
          onPressed: _redoStack.isNotEmpty ? _redo : null,
        ),
        IconButton(
          tooltip: 'Before / After (B)',
          icon: Icon(Icons.compare, size: 18, color: _showBeforeAfter ? const Color(0xFFDCA353) : Colors.white70),
          onPressed: () => setState(() => _showBeforeAfter = !_showBeforeAfter),
        ),
        IconButton(
          tooltip: '3분할 구도선 가이드 (G)',
          icon: Icon(Icons.grid_3x3, size: 18, color: _showGrid ? const Color(0xFF00D2D3) : Colors.white70),
          onPressed: () => setState(() => _showGrid = !_showGrid),
        ),
        const SizedBox(width: 8),

        // 내보내기 버튼 (Ctrl+S)
        ElevatedButton.icon(
          onPressed: () => _exportImage('jpg'),
          icon: const Icon(Icons.file_upload_outlined, size: 16, color: Colors.black),
          label: const Text('내보내기', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDCA353),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  /// 모듈 1: 노출 및 블랙 레벨
  Widget _buildExposureModule() {
    return _buildModuleCard(
      title: '노출 및 블랙 레벨 (Exposure)',
      icon: Icons.wb_iridescent_outlined,
      children: [
        ControlSlider(
          label: '노출 (Exposure EV)',
          value: _params.expEv,
          min: -5.0,
          max: 5.0,
          defaultValue: 0.0,
          unit: ' EV',
          onChanged: (v) => _updateParams((p) => p.expEv = v),
        ),
        ControlSlider(
          label: '블랙 레벨 (Black Level)',
          value: _params.blackLevel,
          min: -0.2,
          max: 0.2,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.blackLevel = v),
        ),
        ControlSlider(
          label: '대비 (Contrast)',
          value: _params.contrast,
          min: -0.8,
          max: 0.8,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.contrast = v),
        ),
      ],
    );
  }

  /// 모듈 2: 화이트 밸런스
  Widget _buildWhiteBalanceModule() {
    return _buildModuleCard(
      title: '화이트 밸런스 (White Balance)',
      icon: Icons.thermostat_outlined,
      children: [
        ControlSlider(
          label: '색온도 (Temperature)',
          value: _params.wbTemperature,
          min: 2000.0,
          max: 12000.0,
          defaultValue: 6500.0,
          fractions: 0,
          unit: ' K',
          onChanged: (v) => _updateParams((p) => p.wbTemperature = v),
        ),
        ControlSlider(
          label: '틴트 (Tint)',
          value: _params.wbTint,
          min: -1.0,
          max: 1.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.wbTint = v),
        ),
      ],
    );
  }

  /// 모듈 3: 톤 커브 (Tone Curve)
  Widget _buildToneCurveModule() {
    return _buildModuleCard(
      title: '톤 커브 (Tone Curve)',
      icon: Icons.timeline,
      children: [
        // RGB 채널 탭
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['RGB', 'R', 'G', 'B'].map((ch) {
            final isCur = _curveChannel == ch;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(ch, style: TextStyle(fontSize: 10, color: isCur ? Colors.white : Colors.grey)),
                selected: isCur,
                onSelected: (_) => setState(() => _curveChannel = ch),
                selectedColor: const Color(0xFFDCA353),
                backgroundColor: const Color(0xFF222222),
              ),
            );
          }).toList(),
        ),

        ToneCurveWidget(
          points: _params.curveRgb,
          activeChannel: _curveChannel,
          onChanged: (pts) => _updateParams((p) {
            p.toneCurveEnabled = true;
            p.curveRgb = pts;
          }),
        ),
      ],
    );
  }

  /// 모듈 4: 5밴드 톤 이퀄라이저
  Widget _buildToneEqualizerModule() {
    return _buildModuleCard(
      title: '5밴드 톤 이퀄라이저 (Tone Equalizer)',
      icon: Icons.equalizer,
      children: [
        ControlSlider(
          label: '블랙 (Blacks)',
          value: _params.teBlacks,
          min: -1.0,
          max: 1.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.teBlacks = v),
        ),
        ControlSlider(
          label: '섀도우 (Shadows)',
          value: _params.teShadows,
          min: -1.0,
          max: 1.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.teShadows = v),
        ),
        ControlSlider(
          label: '미드톤 (Midtones)',
          value: _params.teMidtones,
          min: -1.0,
          max: 1.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.teMidtones = v),
        ),
        ControlSlider(
          label: '하이라이트 (Highlights)',
          value: _params.teHighlights,
          min: -1.0,
          max: 1.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.teHighlights = v),
        ),
        ControlSlider(
          label: '화이트 (Whites)',
          value: _params.teWhites,
          min: -1.0,
          max: 1.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.teWhites = v),
        ),
      ],
    );
  }

  /// 모듈 5: 시그모이드 톤 매핑
  Widget _buildSigmoidModule() {
    return _buildModuleCard(
      title: '시그모이드 톤 매핑 (Sigmoid)',
      icon: Icons.show_chart,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          title: const Text('시그모이드 활성화', style: TextStyle(fontSize: 12.5)),
          value: _params.sigmoidEnabled,
          onChanged: (val) => _updateParams((p) => p.sigmoidEnabled = val),
        ),
        if (_params.sigmoidEnabled) ...[
          ControlSlider(
            label: '대비 (Contrast)',
            value: _params.sigContrast,
            min: 0.5,
            max: 2.5,
            defaultValue: 1.0,
            onChanged: (v) => _updateParams((p) => p.sigContrast = v),
          ),
          ControlSlider(
            label: '스큐 / 중심점 (Skew)',
            value: _params.sigSkew,
            min: -1.0,
            max: 1.0,
            defaultValue: 0.0,
            onChanged: (v) => _updateParams((p) => p.sigSkew = v),
          ),
        ],
      ],
    );
  }

  /// 모듈 6: 8밴드 컬러 이퀄라이저
  Widget _buildColorEqualizerModule() {
    return _buildModuleCard(
      title: '8밴드 컬러 이퀄라이저 (Color Equalizer)',
      icon: Icons.color_lens_outlined,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          title: const Text('컬러 이퀄라이저 활성화', style: TextStyle(fontSize: 12.5)),
          value: _params.colorEqualizerEnabled,
          onChanged: (val) => _updateParams((p) => p.colorEqualizerEnabled = val),
        ),
        if (_params.colorEqualizerEnabled)
          ColorEqualizerWidget(
            ceqHue: _params.ceqHue,
            ceqSat: _params.ceqSat,
            ceqBri: _params.ceqBri,
            onChanged: (idx, h, s, b) => _updateParams((p) {
              p.ceqHue[idx] = h;
              p.ceqSat[idx] = s;
              p.ceqBri[idx] = b;
            }),
          ),
      ],
    );
  }

  /// 모듈 7: 채도 및 생동감
  Widget _buildColorZonesModule() {
    return _buildModuleCard(
      title: '채도 및 생동감 (Color Zones)',
      icon: Icons.palette_outlined,
      children: [
        ControlSlider(
          label: '생동감 (Vibrance)',
          value: _params.satVibrance,
          min: -1.0,
          max: 1.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.satVibrance = v),
        ),
        ControlSlider(
          label: '전역 채도 (Saturation)',
          value: _params.satGlobal,
          min: -1.0,
          max: 1.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.satGlobal = v),
        ),
        ControlSlider(
          label: '하이라이트 복원 (Highlight Recovery)',
          value: _params.hlRecovery,
          min: 0.0,
          max: 1.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.hlRecovery = v),
        ),
      ],
    );
  }

  /// 모듈 8: 디헤이즈 및 비네팅
  Widget _buildDetailEffectsModule() {
    return _buildModuleCard(
      title: '디헤이즈 & 비네팅 (Dehaze & Vignette)',
      icon: Icons.blur_linear,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          title: const Text('디헤이즈 (안개 제거)', style: TextStyle(fontSize: 12.5)),
          value: _params.dehazeEnabled,
          onChanged: (val) => _updateParams((p) => p.dehazeEnabled = val),
        ),
        if (_params.dehazeEnabled)
          ControlSlider(
            label: '디헤이즈 강도',
            value: _params.dhStrength,
            min: -1.0,
            max: 1.0,
            defaultValue: 0.0,
            onChanged: (v) => _updateParams((p) => p.dhStrength = v),
          ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          title: const Text('비네팅 (Vignette)', style: TextStyle(fontSize: 12.5)),
          value: _params.vignetteEnabled,
          onChanged: (val) => _updateParams((p) => p.vignetteEnabled = val),
        ),
        if (_params.vignetteEnabled)
          ControlSlider(
            label: '비네팅 강도',
            value: _params.vgAmount,
            min: 0.0,
            max: 1.0,
            defaultValue: 0.0,
            onChanged: (v) => _updateParams((p) => p.vgAmount = v),
          ),
      ],
    );
  }

  Widget _buildModuleCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
          side: const BorderSide(color: Color(0xFF282828)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Icon(icon, size: 18, color: const Color(0xFFDCA353)),
          title: Text(
            title,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _buildStatusBar(RawImageResult? curImage) {
    final name = curImage?.filename ?? '로드된 사진 없음';
    final resolution = curImage != null ? '${curImage.width} × ${curImage.height} px' : '-';
    final sizeMb = curImage != null ? '${(curImage.fileSize / 1024 / 1024).toStringAsFixed(1)} MB' : '-';

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFF121212),
      child: Row(
        children: [
          const Icon(Icons.image_outlined, size: 13, color: Colors.grey),
          const SizedBox(width: 6),
          Text(name, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(width: 16),
          const Icon(Icons.grid_on, size: 13, color: Colors.grey),
          const SizedBox(width: 6),
          Text(resolution, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(width: 16),
          Text(sizeMb, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const Spacer(),
          if (_isProcessing) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFDCA353)),
            ),
            const SizedBox(width: 8),
            const Text('32-bit Float 연산 중...', style: TextStyle(fontSize: 11, color: Color(0xFFDCA353))),
          ] else ...[
            const Icon(Icons.check_circle_outline, size: 13, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              curImage?.isRaw == true ? 'Sony ARW / 14-bit Pure RAW' : '32-bit ACEScg Float',
              style: const TextStyle(fontSize: 11, color: Colors.green),
            ),
          ],
        ],
      ),
    );
  }

  RawImageResult _createSampleScene() {
    const width = 1280;
    const height = 720;
    final image = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final ny = y / height;
      for (int x = 0; x < width; x++) {
        final nx = x / width;

        double r = (1.0 - ny) * 0.4 + 0.3;
        double g = (1.0 - ny) * 0.5 + 0.4;
        double b = (1.0 - ny) * 0.9 + 0.1;

        final sunDx = nx - 0.7;
        final sunDy = ny - 0.3;
        final sunDist = math.sqrt(sunDx * sunDx + sunDy * sunDy);
        if (sunDist < 0.25) {
          final intensity = math.pow((0.25 - sunDist) / 0.25, 2.0) * 1.5;
          r += intensity * 1.2;
          g += intensity * 0.95;
          b += intensity * 0.7;
        }

        final mountainY = 0.55 + 0.15 * math.sin(nx * 8.0) + 0.08 * math.cos(nx * 14.0);
        if (ny > mountainY) {
          final depth = (ny - mountainY) / (1.0 - mountainY);
          r = 0.04 + depth * 0.05;
          g = 0.07 + depth * 0.08;
          b = 0.05 + depth * 0.06;
        }

        image.setPixelRgba(
          x,
          y,
          (r.clamp(0.0, 1.0) * 255).round(),
          (g.clamp(0.0, 1.0) * 255).round(),
          (b.clamp(0.0, 1.0) * 255).round(),
          255,
        );
      }
    }

    return RawImageResult(
      filename: 'Sample_Landscape_32bit.raw',
      filepath: 'sample://landscape',
      fileSize: 1280 * 720 * 4,
      ext: 'RAW',
      width: width,
      height: height,
      isRaw: true,
      bitDepthStr: '32-bit Float RAW Scene',
      rawImage: image,
      previewImage: image,
    );
  }
}

/// 3분할 9칸 점선 구도선 가이드 페인터 (G)
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x6600D2D3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    // 세로 2줄
    canvas.drawLine(Offset(w / 3.0, 0), Offset(w / 3.0, h), paint);
    canvas.drawLine(Offset(w * 2.0 / 3.0, 0), Offset(w * 2.0 / 3.0, h), paint);

    // 가로 2줄
    canvas.drawLine(Offset(0, h / 3.0), Offset(w, h / 3.0), paint);
    canvas.drawLine(Offset(0, h * 2.0 / 3.0), Offset(w, h * 2.0 / 3.0), paint);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
