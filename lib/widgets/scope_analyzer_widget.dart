import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/scopes.dart';

/// SemiDarktable의 ScopeWidget 1:1 이식
/// - 4개 분석 모드 탭: Waveform, Parade, Histogram, 8-Band
/// - Waveform/Parade/Histogram은 계산된 RGBA 버퍼를 GPU 텍스처(ui.Image)로 변환하여 즉시 렌더링
/// - 8-Band는 8개 색상 대역의 평균 채도x밝기 에너지를 컬러 막대 그래프로 렌더링
class ScopeAnalyzerWidget extends StatefulWidget {
  final ScopeData? scopeData;

  const ScopeAnalyzerWidget({
    super.key,
    required this.scopeData,
  });

  @override
  State<ScopeAnalyzerWidget> createState() => _ScopeAnalyzerWidgetState();
}

class _ScopeAnalyzerWidgetState extends State<ScopeAnalyzerWidget> {
  String _mode = 'waveform'; // 'waveform', 'parade', 'histogram', 'bands'
  ui.Image? _waveformImg;
  ui.Image? _paradeImg;
  ui.Image? _histogramImg;

  @override
  void initState() {
    super.initState();
    _rebuildScopeImages();
  }

  @override
  void didUpdateWidget(covariant ScopeAnalyzerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeData != widget.scopeData) {
      _rebuildScopeImages();
    }
  }

  @override
  void dispose() {
    _waveformImg?.dispose();
    _paradeImg?.dispose();
    _histogramImg?.dispose();
    super.dispose();
  }

  Future<void> _rebuildScopeImages() async {
    final data = widget.scopeData;
    if (data == null) return;

    final wf = await _rgbaToUiImage(data.waveformRgba, kScopeW, kScopeH);
    final pr = await _rgbaToUiImage(data.paradeRgba, kScopeW, kScopeH);
    final hs = await _rgbaToUiImage(data.histogramRgba, kScopeW, kScopeH);

    if (!mounted) {
      wf.dispose();
      pr.dispose();
      hs.dispose();
      return;
    }
    setState(() {
      _waveformImg?.dispose();
      _paradeImg?.dispose();
      _histogramImg?.dispose();
      _waveformImg = wf;
      _paradeImg = pr;
      _histogramImg = hs;
    });
  }

  Future<ui.Image> _rgbaToUiImage(
    dynamic rgbaBytes,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) => completer.complete(img),
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF343434)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 4개 스코프 모드 전환 버튼
          Row(
            children: [
              for (final m in [
                ('waveform', 'Waveform'),
                ('parade', 'Parade'),
                ('histogram', 'Histogram'),
                ('bands', '8-Band'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: InkWell(
                      onTap: () => setState(() => _mode = m.$1),
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _mode == m.$1
                              ? const Color(0xFF3E3524)
                              : const Color(0xFF181818),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: _mode == m.$1
                                ? const Color(0xFFE8A838)
                                : const Color(0xFF333333),
                          ),
                        ),
                        child: Text(
                          m.$2,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: _mode == m.$1
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _mode == m.$1
                                ? const Color(0xFFE8A838)
                                : const Color(0xFF999999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 스코프 표시 캔버스
          Container(
            height: 125,
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF2D2D2D)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: _buildScopeBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeBody() {
    if (widget.scopeData == null) {
      return const Center(
        child: Text(
          '이미지를 불러오면 실시간 파형/히스토그램이 표시됩니다',
          style: TextStyle(fontSize: 11, color: Color(0xFF666666)),
        ),
      );
    }

    if (_mode == 'bands') {
      return CustomPaint(
        size: const Size(double.infinity, 125),
        painter: _EightBandPainter(levels: widget.scopeData!.bandLevels),
      );
    }

    ui.Image? targetImg;
    if (_mode == 'waveform') {
      targetImg = _waveformImg;
    } else if (_mode == 'parade') {
      targetImg = _paradeImg;
    } else {
      targetImg = _histogramImg;
    }

    if (targetImg == null) {
      return const SizedBox.expand();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        RawImage(
          image: targetImg,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
        ),
        CustomPaint(
          painter: _ScopeOverlayGridPainter(isParade: _mode == 'parade'),
        ),
      ],
    );
  }
}

class _ScopeOverlayGridPainter extends CustomPainter {
  final bool isParade;
  _ScopeOverlayGridPainter({required this.isParade});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x28FFFFFF)
      ..strokeWidth = 0.8;
    for (int i = 1; i < 4; i++) {
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    if (isParade) {
      for (int i = 1; i < 3; i++) {
        final x = size.width * (i / 3.0);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScopeOverlayGridPainter oldDelegate) =>
      oldDelegate.isParade != isParade;
}

class _EightBandPainter extends CustomPainter {
  final List<double> levels;
  _EightBandPainter({required this.levels});

  static const List<String> _names = [
    'Red',
    'Org',
    'Yel',
    'Grn',
    'Aqu',
    'Blu',
    'Pur',
    'Mag',
  ];

  static const List<Color> _colors = [
    Color(0xFFFF4040),
    Color(0xFFFF8830),
    Color(0xFFFFDD30),
    Color(0xFF45DD45),
    Color(0xFF30DDDD),
    Color(0xFF4588FF),
    Color(0xFF9955FF),
    Color(0xFFFF45CC),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const padX = 12.0;
    const padTop = 14.0;
    const padBot = 20.0;
    final usableW = (size.width - padX * 2).clamp(1.0, 10000.0);
    final usableH = (size.height - padTop - padBot).clamp(1.0, 10000.0);
    final slotW = usableW / 8.0;
    final barW = slotW * 0.58;

    for (int i = 0; i < 8; i++) {
      final lv = (i < levels.length ? levels[i] : 0.0).clamp(0.0, 1.0);
      final bh = lv * usableH;
      final cx = padX + slotW * (i + 0.5);
      final left = cx - barW * 0.5;
      final top = padTop + usableH - bh;

      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barW, bh),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        barRect,
        Paint()..color = _colors[i].withValues(alpha: 0.85),
      );

      // 퍼센트 수치
      final pctTp = TextPainter(
        text: TextSpan(
          text: '${(lv * 100).round()}%',
          style: const TextStyle(fontSize: 8.5, color: Color(0xFFCCCCCC)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      pctTp.paint(canvas, Offset(cx - pctTp.width * 0.5, top - 11));

      // 밴드 라벨
      final lblTp = TextPainter(
        text: TextSpan(
          text: _names[i],
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: _colors[i],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      lblTp.paint(
        canvas,
        Offset(cx - lblTp.width * 0.5, size.height - padBot + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EightBandPainter oldDelegate) => true;
}
