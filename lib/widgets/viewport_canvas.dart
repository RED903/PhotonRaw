import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// 고품질 인터랙티브 뷰포트 캔버스
/// Pan, Zoom(마우스 휠 / 핀치 줌), Before/After 원본 비교 기능을 제공합니다.
class ViewportCanvas extends StatefulWidget {
  final img.Image? processedImage;
  final img.Image? originalImage;
  final bool showBeforeAfter;
  final TransformationController transformController;

  const ViewportCanvas({
    super.key,
    required this.processedImage,
    required this.originalImage,
    required this.showBeforeAfter,
    required this.transformController,
  });

  @override
  State<ViewportCanvas> createState() => _ViewportCanvasState();
}

class _ViewportCanvasState extends State<ViewportCanvas> {
  Uint8List? _processedBytes;
  Uint8List? _originalBytes;
  img.Image? _lastProcessedRef;
  img.Image? _lastOriginalRef;
  double _splitRatio = 0.5; // Before/After 분할 비율 (0.0 ~ 1.0)

  @override
  void didUpdateWidget(covariant ViewportCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateBytesIfNeeded();
  }

  @override
  void initState() {
    super.initState();
    _updateBytesIfNeeded();
  }

  void _updateBytesIfNeeded() {
    if (widget.processedImage != _lastProcessedRef && widget.processedImage != null) {
      _lastProcessedRef = widget.processedImage;
      _processedBytes = Uint8List.fromList(img.encodeBmp(widget.processedImage!));
    }
    if (widget.originalImage != _lastOriginalRef && widget.originalImage != null) {
      _lastOriginalRef = widget.originalImage;
      _originalBytes = Uint8List.fromList(img.encodeBmp(widget.originalImage!));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_processedBytes == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 72, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              'RAW 또는 이미지 파일을 열어주세요',
              style: TextStyle(color: Colors.grey[500], fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              '상단 [파일 열기] 버튼이나 [샘플 씬 로드]를 클릭하세요',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: const Color(0xFF161616),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 체커보드 배경 패턴
              CustomPaint(
                painter: _CheckerboardPainter(),
              ),

              // Pan & Zoom 지원 InteractiveViewer
              InteractiveViewer(
                transformationController: widget.transformController,
                minScale: 0.1,
                maxScale: 10.0,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Center(
                  child: widget.showBeforeAfter && _originalBytes != null
                      ? _buildBeforeAfterSplit()
                      : Image.memory(
                          _processedBytes!,
                          filterQuality: FilterQuality.medium,
                        ),
                ),
              ),

              // Before/After 텍스트 인디케이터
              if (widget.showBeforeAfter)
                Positioned(
                  top: 16,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'BEFORE (원본) | AFTER (보정본)',
                      style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBeforeAfterSplit() {
    return Stack(
      children: [
        // 원본 (Before)
        Image.memory(_originalBytes!),
        // 보정본 (After) 클립
        ClipRect(
          clipper: _SplitClipper(_splitRatio),
          child: Image.memory(_processedBytes!),
        ),
      ],
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  final double ratio;
  _SplitClipper(this.ratio);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(size.width * (1.0 - ratio), 0, size.width * ratio, size.height);
  }

  @override
  bool shouldReclip(covariant _SplitClipper oldClipper) => oldClipper.ratio != ratio;
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const squareSize = 16.0;
    final paint1 = Paint()..color = const Color(0xFF1C1C1C);
    final paint2 = Paint()..color = const Color(0xFF181818);

    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        final isEven = ((x / squareSize).floor() + (y / squareSize).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, squareSize, squareSize),
          isEven ? paint1 : paint2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) => false;
}
