import 'dart:async';
import 'dart:io';
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
import 'widgets/control_slider.dart';
import 'widgets/histogram_widget.dart';
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
      title: 'PhotonRaw - Professional RAW Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF191919),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141414),
          elevation: 0,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF64B5F6),
          secondary: Color(0xFF42A5F5),
          surface: Color(0xFF222222),
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
  RawImageResult? _currentImage;
  img.Image? _processedPreview;
  HistogramData? _histogram;

  PipelineParams _params = PipelineParams();
  final TransformationController _transformController = TransformationController();

  bool _isProcessing = false;
  bool _showBeforeAfter = false;
  bool _isDragging = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadSampleScene();
  }

  /// 초기 기본 씬 로드
  void _loadSampleScene() {
    final sample = _createSampleScene();
    setState(() {
      _currentImage = sample;
    });
    _triggerPipeline(immediate: true);
  }

  /// 파일 직접 열기 (탐색기)
  Future<void> _openFilePicker() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'arw', 'cr2', 'cr3', 'nef', 'dng', 'raf', 'orf', 'rw2', // RAW
          'jpg', 'jpeg', 'png', 'tiff', 'tif', 'webp', 'bmp'      // 표준 이미지
        ],
      );

      if (result.isEmpty) return;
      final file = result.first;
      final path = file.path;

      if (path != null) {
        await _loadFileFromPath(path);
      } else {
        final bytes = await file.readAsBytes();
        _loadFromBytes(bytes, file.name);
      }
    } catch (e) {
      _showError('파일 열기 실패: $e');
    }
  }

  /// 드래그 앤 드롭 또는 파일 경로로부터 로드
  Future<void> _loadFileFromPath(String path) async {
    setState(() => _isProcessing = true);
    try {
      final loaded = await RawDecoder.loadFromFile(path);
      setState(() {
        _currentImage = loaded;
        _params = PipelineParams();
      });
      _triggerPipeline(immediate: true);
    } catch (e) {
      _showError('RAW 로딩 실패: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _loadFromBytes(Uint8List bytes, String filename) {
    setState(() => _isProcessing = true);
    try {
      final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
      final loaded = RawDecoder.decodeBytes(bytes, filename: filename, filepath: filename, ext: ext);
      setState(() {
        _currentImage = loaded;
        _params = PipelineParams();
      });
      _triggerPipeline(immediate: true);
    } catch (e) {
      _showError('디코딩 실패: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red[800], content: Text(message)),
    );
  }

  /// 이미지 내보내기 (Export)
  Future<void> _exportImage(String format) async {
    if (_currentImage == null) return;

    setState(() => _isProcessing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('고해상도 32-bit Float 렌더링 중 ($format)...')),
    );

    await Future.delayed(const Duration(milliseconds: 50));
    final fullResult = PipelineEngine.process(
      sourceImage: _currentImage!.rawImage,
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
      fileName: 'PhotonRaw_${_currentImage!.filename.replaceAll(RegExp(r'\.[^.]+$'), '')}.$format',
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

  void _updateParams(void Function(PipelineParams p) update) {
    setState(() {
      update(_params);
    });
    _triggerPipeline(immediate: false);
  }

  void _triggerPipeline({bool immediate = false}) {
    if (_currentImage == null) return;

    _debounceTimer?.cancel();
    if (immediate) {
      _runPipeline();
    } else {
      _debounceTimer = Timer(const Duration(milliseconds: 16), _runPipeline);
    }
  }

  void _runPipeline() {
    if (_currentImage == null) return;
    final result = PipelineEngine.process(
      sourceImage: _currentImage!.previewImage,
      params: _params,
    );
    setState(() {
      _processedPreview = result.image;
      _histogram = result.histogram;
    });
  }

  void _applyPreset(Preset preset) {
    setState(() {
      _params = preset.params.clone();
    });
    _triggerPipeline(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final presets = PresetService.getBuiltinPresets();

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) async {
        setState(() => _isDragging = false);
        if (details.files.isNotEmpty) {
          final file = details.files.first;
          await _loadFileFromPath(file.path);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lens_blur, color: Color(0xFF64B5F6), size: 22),
              const SizedBox(width: 8),
              const Text('PhotonRaw', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF263238),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _currentImage?.bitDepthStr ?? '32-bit Float',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF81D4FA), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '파일 열기 (Sony ARW, Canon CR2, Nikon NEF, DNG 등)',
              icon: const Icon(Icons.folder_open, size: 20),
              onPressed: _openFilePicker,
            ),
            IconButton(
              tooltip: '샘플 씬 로드',
              icon: const Icon(Icons.wb_sunny_outlined, size: 20),
              onPressed: _loadSampleScene,
            ),
            PopupMenuButton<String>(
              tooltip: '내보내기 (Export)',
              icon: const Icon(Icons.file_download_outlined, size: 20, color: Color(0xFF64B5F6)),
              onSelected: _exportImage,
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'jpg', child: Text('JPEG (96% 고품질)')),
                const PopupMenuItem(value: 'png', child: Text('PNG (무손실 8-bit)')),
                const PopupMenuItem(value: 'tiff', child: Text('TIFF (16-bit Master TIFF)')),
              ],
            ),
            IconButton(
              tooltip: '1:1 화면 맞춤',
              icon: const Icon(Icons.aspect_ratio, size: 20),
              onPressed: () => _transformController.value = Matrix4.identity(),
            ),
            IconButton(
              tooltip: 'Before / After 분할 비교 토글',
              icon: Icon(
                Icons.compare,
                size: 20,
                color: _showBeforeAfter ? Colors.amber : Colors.white70,
              ),
              onPressed: () => setState(() => _showBeforeAfter = !_showBeforeAfter),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            Row(
              children: [
                // 1. 메인 뷰포트
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: ViewportCanvas(
                          processedImage: _processedPreview,
                          originalImage: _currentImage?.previewImage,
                          showBeforeAfter: _showBeforeAfter,
                          transformController: _transformController,
                        ),
                      ),
                      _buildStatusBar(),
                    ],
                  ),
                ),

                // 2. 우측 보정 패널
                Container(
                  width: 350,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1B1B1B),
                    border: Border(left: BorderSide(color: Color(0xFF2C2C2C))),
                  ),
                  child: Column(
                    children: [
                      // 프리셋 바
                      _buildPresetBar(presets),
                      const Divider(height: 1, color: Color(0xFF2C2C2C)),

                      // 실시간 히스토그램 스코프
                      HistogramWidget(data: _histogram),
                      const Divider(height: 1, color: Color(0xFF2C2C2C)),

                      // 세부 조절 섹션 목록
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            _buildExposureSection(),
                            _buildWhiteBalanceSection(),
                            _buildToneEqualizerSection(),
                            _buildSigmoidSection(),
                            _buildColorZonesSection(),
                            _buildDetailEffectsSection(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 드래그 앤 드롭 오버레이 안내
            if (_isDragging)
              Container(
                color: Colors.black.withOpacity(0.75),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF64B5F6), width: 2),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_download, size: 64, color: Color(0xFF64B5F6)),
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

  Widget _buildPresetBar(List<Preset> presets) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF161616),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF64B5F6), size: 16),
          const SizedBox(width: 8),
          const Text('프리셋:', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: 'select',
                isDense: true,
                isExpanded: true,
                dropdownColor: const Color(0xFF242424),
                style: const TextStyle(fontSize: 12, color: Colors.white),
                items: [
                  const DropdownMenuItem(value: 'select', child: Text('스타일 프리셋 선택...')),
                  ...presets.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))),
                ],
                onChanged: (id) {
                  if (id == null || id == 'select') return;
                  final match = presets.firstWhere((p) => p.id == id);
                  _applyPreset(match);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 1. 노출 (Exposure)
  Widget _buildExposureSection() {
    return _buildSectionCard(
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

  /// 2. 화이트 밸런스 (White Balance)
  Widget _buildWhiteBalanceSection() {
    return _buildSectionCard(
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

  /// 3. 5밴드 톤 이퀄라이저 (Tone Equalizer)
  Widget _buildToneEqualizerSection() {
    return _buildSectionCard(
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

  /// 4. 시그모이드 톤 매핑 (Sigmoid Tone Mapping)
  Widget _buildSigmoidSection() {
    return _buildSectionCard(
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
            label: '시그모이드 대비 (Contrast)',
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

  /// 5. 채도 및 생동감 (Color Zones)
  Widget _buildColorZonesSection() {
    return _buildSectionCard(
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

  /// 6. 디헤이즈 및 비네팅
  Widget _buildDetailEffectsSection() {
    return _buildSectionCard(
      title: '효과 및 보정 (Dehaze & Vignette)',
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

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: const Color(0xFF222222),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFF2E2E2E)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Icon(icon, size: 18, color: const Color(0xFF64B5F6)),
          title: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final name = _currentImage?.filename ?? '로드된 이미지 없음';
    final resolution = _currentImage != null ? '${_currentImage!.width} × ${_currentImage!.height} px' : '-';
    final sizeKb = _currentImage != null ? '${(_currentImage!.fileSize / 1024 / 1024).toStringAsFixed(1)} MB' : '-';

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFF141414),
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
          Text(sizeKb, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const Spacer(),
          if (_isProcessing) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF64B5F6)),
            ),
            const SizedBox(width: 8),
            const Text('연산 중...', style: TextStyle(fontSize: 11, color: Color(0xFF64B5F6))),
          ] else ...[
            const Icon(Icons.check_circle_outline, size: 13, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              _currentImage?.isRaw == true ? 'Sony/Bayer 14-bit RAW Native' : '32-bit Float Pipeline',
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
