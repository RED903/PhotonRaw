import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'models/pipeline_params.dart';
import 'services/image_service.dart';
import 'services/pipeline_engine.dart';
import 'services/preset_service.dart';
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
      title: 'PhotonRaw - Cross-Platform RAW Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF181818),
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
  LoadedImage? _currentImage;
  img.Image? _processedPreview;
  HistogramData? _histogram;

  PipelineParams _params = PipelineParams();
  final TransformationController _transformController = TransformationController();

  bool _isProcessing = false;
  bool _showBeforeAfter = false;
  String _selectedPresetId = 'reset';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadSampleScene();
  }

  void _loadSampleScene() {
    final sample = ImageService.createSampleScene();
    setState(() {
      _currentImage = sample;
    });
    _triggerPipeline(immediate: true);
  }

  /// 파일 열기
  Future<void> _openImageFile() async {
    try {
      final loaded = await ImageService.pickAndLoadImage();
      if (loaded != null) {
        setState(() {
          _currentImage = loaded;
          _params = PipelineParams();
          _selectedPresetId = 'reset';
        });
        _triggerPipeline(immediate: true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('파일 열기 실패: $e')),
      );
    }
  }

  /// 이미지 내보내기 (Export)
  Future<void> _exportImage(String format) async {
    if (_currentImage == null) return;

    setState(() => _isProcessing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('고해상도 마스터 렌더링 중 ($format)...')),
    );

    await Future.delayed(const Duration(milliseconds: 50));
    final fullResult = PipelineEngine.process(
      sourceImage: _currentImage!.rawImage,
      params: _params,
    );

    final savedPath = await ImageService.exportImage(
      image: fullResult.image,
      defaultName: _currentImage!.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
      format: format,
    );

    setState(() => _isProcessing = false);
    if (!mounted) return;

    if (savedPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green[800],
          content: Text('성공적으로 저장되었습니다:\n$savedPath'),
        ),
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
      _debounceTimer = Timer(const Duration(milliseconds: 16), () {
        _runPipeline();
      });
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
      _selectedPresetId = preset.id;
      _params = preset.params.clone();
    });
    _triggerPipeline(immediate: true);
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final presets = PresetService.getBuiltinPresets();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lens_blur, color: Color(0xFF64B5F6), size: 22),
            SizedBox(width: 8),
            Text(
              'PhotonRaw',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '파일 열기',
            icon: const Icon(Icons.folder_open, size: 20),
            onPressed: _openImageFile,
          ),
          IconButton(
            tooltip: '샘플 씬 로드',
            icon: const Icon(Icons.wb_sunny_outlined, size: 20),
            onPressed: _loadSampleScene,
          ),
          PopupMenuButton<String>(
            tooltip: '이미지 내보내기',
            onSelected: _exportImage,
            icon: const Icon(Icons.file_download_outlined, size: 20, color: Color(0xFF64B5F6)),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'jpg', child: Text('JPEG로 내보내기 (95% 품질)')),
              const PopupMenuItem(value: 'png', child: Text('PNG로 내보내기 (무손실)')),
              const PopupMenuItem(value: 'tiff', child: Text('TIFF로 내보내기 (16-bit Master)')),
            ],
          ),
          IconButton(
            tooltip: '화면 맞춤 (1:1 줌 리셋)',
            icon: const Icon(Icons.aspect_ratio, size: 20),
            onPressed: _resetZoom,
          ),
          IconButton(
            tooltip: 'Before / After 분할 비교 토글',
            icon: Icon(
              Icons.compare,
              size: 20,
              color: _showBeforeAfter ? Colors.amber : Colors.white70,
            ),
            onPressed: () {
              setState(() => _showBeforeAfter = !_showBeforeAfter);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // 1. 메인 인터랙티브 뷰포트
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

          // 2. 우측 보정 컨트롤러 패널 (Darktable 스타일)
          Container(
            width: 330,
            decoration: const BoxDecoration(
              color: Color(0xFF1B1B1B),
              border: Border(left: BorderSide(color: Color(0xFF2C2C2C))),
            ),
            child: Column(
              children: [
                _buildPresetSelector(presets),
                const Divider(height: 1, color: Color(0xFF2C2C2C)),

                HistogramWidget(data: _histogram),
                const Divider(height: 1, color: Color(0xFF2C2C2C)),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      _buildExposureSection(),
                      _buildColorSection(),
                      _buildSigmoidSection(),
                      _buildToneDetailSection(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSelector(List<Preset> presets) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF181818),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF64B5F6), size: 16),
          const SizedBox(width: 8),
          const Text('프리셋:', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPresetId,
                isDense: true,
                isExpanded: true,
                dropdownColor: const Color(0xFF242424),
                style: const TextStyle(fontSize: 12, color: Colors.white),
                items: presets.map((p) {
                  return DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (id) {
                  if (id == null) return;
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

  Widget _buildExposureSection() {
    return _buildSectionCard(
      title: '노출 및 명암 (Exposure)',
      icon: Icons.wb_iridescent_outlined,
      children: [
        ControlSlider(
          label: '노출 (Exposure EV)',
          value: _params.exposureEv,
          min: -4.0,
          max: 4.0,
          defaultValue: 0.0,
          unit: ' EV',
          onChanged: (v) => _updateParams((p) => p.exposureEv = v),
        ),
        ControlSlider(
          label: '블랙 레벨 (Black Level)',
          value: _params.blackLevel,
          min: -0.15,
          max: 0.15,
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

  Widget _buildColorSection() {
    return _buildSectionCard(
      title: '화이트 밸런스 & 색상 (Color)',
      icon: Icons.palette_outlined,
      children: [
        ControlSlider(
          label: '색온도 (Temperature)',
          value: _params.temperature,
          min: -50.0,
          max: 50.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.temperature = v),
        ),
        ControlSlider(
          label: '틴트 (Tint)',
          value: _params.tint,
          min: -50.0,
          max: 50.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.tint = v),
        ),
        ControlSlider(
          label: '생동감 (Vibrance)',
          value: _params.vibrance,
          min: -100.0,
          max: 100.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.vibrance = v),
        ),
        ControlSlider(
          label: '채도 (Saturation)',
          value: _params.saturation,
          min: -100.0,
          max: 100.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.saturation = v),
        ),
      ],
    );
  }

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
            max: 2.2,
            defaultValue: 1.0,
            onChanged: (v) => _updateParams((p) => p.sigContrast = v),
          ),
          ControlSlider(
            label: '스큐 / 중심점 (Skew)',
            value: _params.sigSkew,
            min: -0.5,
            max: 0.5,
            defaultValue: 0.0,
            onChanged: (v) => _updateParams((p) => p.sigSkew = v),
          ),
        ],
      ],
    );
  }

  Widget _buildToneDetailSection() {
    return _buildSectionCard(
      title: '디테일 및 복원 (Highlights & Shadows)',
      icon: Icons.wb_twilight,
      children: [
        ControlSlider(
          label: '하이라이트 복원 (Highlights)',
          value: _params.highlights,
          min: -100.0,
          max: 100.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.highlights = v),
        ),
        ControlSlider(
          label: '섀도우 밝기 복원 (Shadows)',
          value: _params.shadows,
          min: -100.0,
          max: 100.0,
          defaultValue: 0.0,
          onChanged: (v) => _updateParams((p) => p.shadows = v),
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
    final name = _currentImage?.name ?? '로드된 이미지 없음';
    final resolution = _currentImage != null ? '${_currentImage!.width} × ${_currentImage!.height} px' : '-';

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
            const Text('Ready (ACEScg 32-bit Float)', style: TextStyle(fontSize: 11, color: Colors.green)),
          ],
        ],
      ),
    );
  }
}
