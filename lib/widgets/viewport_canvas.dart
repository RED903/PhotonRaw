import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/pipeline_params.dart';

/// SemiDarktable의 GLImageViewport 인터랙션 및 오버레이 1:1 이식
/// - BMP 재인코딩 없이 GPU 텍스처(ui.Image)를 직접 CustomPainter로 렌더링하여 창 크기 조절 시 크래시/멈춤 원천 차단
/// - 빈 화면 상태 제공 (이상한 물결 샘플 이미지 완전 제거)
/// - Before/After 분할 비교 뷰 (드래그 가능한 분할선)
/// - 3x3 구도 격자 오버레이 (G)
/// - 인터랙티브 크롭 박스 편집 모드 (모서리/변/내부 드래그 및 화면비 고정 지원)
/// - 2점 수평선 그리기 모드 (두 점 드래그로 기울기 각도 자동 계산)
/// - 화이트밸런스 스포이드 모드 (클릭 지점 뉴트럴 픽셀 샘플링)
/// - 잡티 제거(Spot Removal) 인터랙티브 추가/드래그/우클릭 삭제 모드
class ViewportCanvas extends StatefulWidget {
  final ui.Image? processedImage;
  final ui.Image? beforeImage;
  final PipelineParams params;
  final bool showGrid;
  final bool cropEditMode;
  final double? cropAspectRatio; // null = 자유 비율
  final bool horizonMode;
  final bool wbPickerMode;
  final bool spotEditMode;
  final double newSpotRadius;
  final VoidCallback onOpenFileRequested;
  final ValueChanged<double> onSplitPositionChanged;
  final ValueChanged<List<double>> onCropRectChanged;
  final ValueChanged<double> onHorizonAngleComputed;
  final void Function(double normX, double normY) onWbSamplePicked;
  final ValueChanged<List<Spot>> onSpotsChanged;

  const ViewportCanvas({
    super.key,
    required this.processedImage,
    required this.beforeImage,
    required this.params,
    required this.showGrid,
    required this.cropEditMode,
    required this.cropAspectRatio,
    required this.horizonMode,
    required this.wbPickerMode,
    required this.spotEditMode,
    required this.newSpotRadius,
    required this.onOpenFileRequested,
    required this.onSplitPositionChanged,
    required this.onCropRectChanged,
    required this.onHorizonAngleComputed,
    required this.onWbSamplePicked,
    required this.onSpotsChanged,
  });

  @override
  State<ViewportCanvas> createState() => ViewportCanvasState();
}

class ViewportCanvasState extends State<ViewportCanvas> {
  double _zoom = 1.0;
  double _scaleStartZoom = 1.0;
  Offset _pan = Offset.zero;
  bool _isPinching = false;

  bool _draggingSplit = false;
  String? _cropDragHandle; // 'tl','tr','bl','br','move'
  Offset? _cropDragStartNorm;
  List<double>? _cropRectAtStart;

  Offset? _horizonStart;
  Offset? _horizonEnd;

  int? _draggingSpotIndex;

  /// 외부에서 줌/팬 초기화 호출용
  void resetZoom() {
    setState(() {
      _zoom = 1.0;
      _pan = Offset.zero;
    });
  }

  /// 캔버스 크기 내에서 이미지가 그려지는 실제 사각형 영역 계산
  Rect _computeImageRect(Size canvasSize) {
    final img = widget.processedImage;
    if (img == null || canvasSize.width <= 0 || canvasSize.height <= 0) {
      return Rect.zero;
    }
    const pad = 16.0;
    final availW = math.max(1.0, canvasSize.width - pad * 2);
    final availH = math.max(1.0, canvasSize.height - pad * 2);
    final imgAspect = img.width / math.max(1, img.height);
    final canvasAspect = availW / availH;

    double drawW;
    double drawH;
    if (imgAspect > canvasAspect) {
      drawW = availW;
      drawH = availW / imgAspect;
    } else {
      drawH = availH;
      drawW = availH * imgAspect;
    }

    drawW *= _zoom;
    drawH *= _zoom;

    final cx = canvasSize.width * 0.5 + _pan.dx;
    final cy = canvasSize.height * 0.5 + _pan.dy;
    return Rect.fromCenter(center: Offset(cx, cy), width: drawW, height: drawH);
  }

  Offset? _localToImageNorm(Offset localPos, Rect imgRect) {
    if (imgRect.width <= 1 || imgRect.height <= 1) return null;
    final nx = (localPos.dx - imgRect.left) / imgRect.width;
    final ny = (localPos.dy - imgRect.top) / imgRect.height;
    return Offset(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
  }

  String _hitTestCropHandle(Offset pos, Rect imgRect, List<double> cropRect) {
    final cl = imgRect.left + cropRect[0] * imgRect.width;
    final ct = imgRect.top + cropRect[1] * imgRect.height;
    final cr = imgRect.left + (cropRect[0] + cropRect[2]) * imgRect.width;
    final cb = imgRect.top + (cropRect[1] + cropRect[3]) * imgRect.height;

    const hitR = 16.0;
    if ((pos - Offset(cl, ct)).distance <= hitR) return 'tl';
    if ((pos - Offset(cr, ct)).distance <= hitR) return 'tr';
    if ((pos - Offset(cl, cb)).distance <= hitR) return 'bl';
    if ((pos - Offset(cr, cb)).distance <= hitR) return 'br';
    if (Rect.fromLTRB(cl, ct, cr, cb).contains(pos)) return 'move';
    return 'none';
  }

  void _onPointerSignal(PointerSignalEvent event, Size size) {
    if (event is PointerScrollEvent && widget.processedImage != null) {
      final factor = event.scrollDelta.dy < 0 ? 1.15 : (1.0 / 1.15);
      setState(() {
        _zoom = (_zoom * factor).clamp(0.25, 16.0);
        if ((_zoom - 1.0).abs() < 0.03) {
          _zoom = 1.0;
          _pan = Offset.zero;
        }
      });
    }
  }

  void _onTapUp(TapUpDetails details, Size size) {
    final img = widget.processedImage;
    if (img == null) return;
    final imgRect = _computeImageRect(size);
    final norm = _localToImageNorm(details.localPosition, imgRect);
    if (norm == null) return;

    // 1. 화이트밸런스 스포이드 모드
    if (widget.wbPickerMode) {
      widget.onWbSamplePicked(norm.dx, norm.dy);
      return;
    }

    // 2. 잡티 제거(Spot Removal) 클릭 추가
    if (widget.spotEditMode) {
      final spots = widget.params.spots.map((s) => s.clone()).toList();
      // 기존 스팟 위를 클릭했는지 확인
      for (int i = 0; i < spots.length; i++) {
        final sx = imgRect.left + spots[i].x * imgRect.width;
        final sy = imgRect.top + spots[i].y * imgRect.height;
        if ((Offset(sx, sy) - details.localPosition).distance <= 14.0) {
          return;
        }
      }
      final offsetNorm = (widget.newSpotRadius * 2.2).clamp(0.02, 0.15);
      final srcX = (norm.dx + offsetNorm <= 0.96)
          ? norm.dx + offsetNorm
          : norm.dx - offsetNorm;
      spots.add(
        Spot(
          x: norm.dx,
          y: norm.dy,
          srcX: srcX.clamp(0.02, 0.98),
          srcY: norm.dy,
          r: widget.newSpotRadius,
        ),
      );
      widget.onSpotsChanged(spots);
    }
  }

  void _onSecondaryTapUp(TapUpDetails details, Size size) {
    // 우클릭 시 해당 위치의 잡티 제거 포인트 삭제
    if (!widget.spotEditMode || widget.processedImage == null) return;
    final imgRect = _computeImageRect(size);
    final spots = widget.params.spots.map((s) => s.clone()).toList();
    for (int i = spots.length - 1; i >= 0; i--) {
      final sx = imgRect.left + spots[i].x * imgRect.width;
      final sy = imgRect.top + spots[i].y * imgRect.height;
      if ((Offset(sx, sy) - details.localPosition).distance <= 18.0) {
        spots.removeAt(i);
        widget.onSpotsChanged(spots);
        return;
      }
    }
  }

  void _onScaleStart(ScaleStartDetails details, Size size) {
    final img = widget.processedImage;
    if (img == null) return;
    _scaleStartZoom = _zoom;

    // 두 손가락 이상(핀치 줌) 시작 시 편집 드래그 모드를 해제하고 확대/축소에 집중
    if (details.pointerCount >= 2) {
      _isPinching = true;
      _draggingSplit = false;
      _cropDragHandle = null;
      _draggingSpotIndex = null;
      _horizonStart = null;
      _horizonEnd = null;
      return;
    }
    _isPinching = false;

    final imgRect = _computeImageRect(size);
    final pos = details.localFocalPoint;

    // 1. 수평선 2점 그리기 모드
    if (widget.horizonMode) {
      setState(() {
        _horizonStart = pos;
        _horizonEnd = pos;
      });
      return;
    }

    // 2. 크롭 편집 모드
    if (widget.cropEditMode) {
      final handle = _hitTestCropHandle(pos, imgRect, widget.params.cropRect);
      if (handle != 'none') {
        _cropDragHandle = handle;
        _cropDragStartNorm = _localToImageNorm(pos, imgRect);
        _cropRectAtStart = List<double>.from(widget.params.cropRect);
        return;
      }
    }

    // 3. 잡티 제거 포인트 드래그 이동
    if (widget.spotEditMode) {
      final spots = widget.params.spots;
      for (int i = 0; i < spots.length; i++) {
        final sx = imgRect.left + spots[i].x * imgRect.width;
        final sy = imgRect.top + spots[i].y * imgRect.height;
        if ((Offset(sx, sy) - pos).distance <= 16.0) {
          _draggingSpotIndex = i;
          return;
        }
      }
    }

    // 4. Before/After 분할선 드래그
    if (widget.params.splitViewEnabled) {
      final splitX =
          imgRect.left + widget.params.splitPosition * imgRect.width;
      if ((pos.dx - splitX).abs() <= 18.0) {
        _draggingSplit = true;
        return;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size size) {
    final img = widget.processedImage;
    if (img == null) return;

    // 두 손가락 핀치 확대/축소 및 팬 이동 처리 (모바일 멀티터치 완벽 지원)
    if (details.pointerCount >= 2 || _isPinching || (details.scale - 1.0).abs() > 1e-3) {
      _isPinching = true;
      setState(() {
        _zoom = (_scaleStartZoom * details.scale).clamp(0.25, 16.0);
        _pan += details.focalPointDelta;
        if ((_zoom - 1.0).abs() < 0.03) {
          _zoom = 1.0;
        }
      });
      return;
    }

    final imgRect = _computeImageRect(size);
    final pos = details.localFocalPoint;

    // 1. 수평선 그리기 업데이트
    if (widget.horizonMode && _horizonStart != null) {
      setState(() => _horizonEnd = pos);
      return;
    }

    // 2. 크롭 박스 핸들 드래그 업데이트
    if (widget.cropEditMode &&
        _cropDragHandle != null &&
        _cropDragStartNorm != null &&
        _cropRectAtStart != null) {
      final curNorm = _localToImageNorm(pos, imgRect);
      if (curNorm == null) return;
      final dx = curNorm.dx - _cropDragStartNorm!.dx;
      final dy = curNorm.dy - _cropDragStartNorm!.dy;

      double x0 = _cropRectAtStart![0];
      double y0 = _cropRectAtStart![1];
      double x1 = _cropRectAtStart![0] + _cropRectAtStart![2];
      double y1 = _cropRectAtStart![1] + _cropRectAtStart![3];

      const minSpan = 0.05;
      switch (_cropDragHandle) {
        case 'tl':
          x0 = (x0 + dx).clamp(0.0, x1 - minSpan);
          y0 = (y0 + dy).clamp(0.0, y1 - minSpan);
          break;
        case 'tr':
          x1 = (x1 + dx).clamp(x0 + minSpan, 1.0);
          y0 = (y0 + dy).clamp(0.0, y1 - minSpan);
          break;
        case 'bl':
          x0 = (x0 + dx).clamp(0.0, x1 - minSpan);
          y1 = (y1 + dy).clamp(y0 + minSpan, 1.0);
          break;
        case 'br':
          x1 = (x1 + dx).clamp(x0 + minSpan, 1.0);
          y1 = (y1 + dy).clamp(y0 + minSpan, 1.0);
          break;
        case 'move':
          final w = x1 - x0;
          final h = y1 - y0;
          x0 = (x0 + dx).clamp(0.0, 1.0 - w);
          y0 = (y0 + dy).clamp(0.0, 1.0 - h);
          x1 = x0 + w;
          y1 = y0 + h;
          break;
      }

      // 고정 비율(Aspect Ratio) 적용
      if (widget.cropAspectRatio != null && _cropDragHandle != 'move') {
        final targetRatio = widget.cropAspectRatio!;
        final imgAspect = img.width / math.max(1.0, img.height.toDouble());
        final normRatio = targetRatio / imgAspect;
        final w = x1 - x0;
        final newH = (w / normRatio).clamp(minSpan, 1.0 - y0);
        y1 = (y0 + newH).clamp(y0 + minSpan, 1.0);
      }

      widget.onCropRectChanged([x0, y0, x1 - x0, y1 - y0]);
      return;
    }

    // 3. 잡티 제거 포인트 이동
    if (widget.spotEditMode && _draggingSpotIndex != null) {
      final norm = _localToImageNorm(pos, imgRect);
      if (norm == null) return;
      final spots = widget.params.spots.map((s) => s.clone()).toList();
      if (_draggingSpotIndex! < spots.length) {
        final old = spots[_draggingSpotIndex!];
        final dx = norm.dx - old.x;
        final dy = norm.dy - old.y;
        old.x = norm.dx;
        old.y = norm.dy;
        old.srcX = (old.srcX + dx).clamp(0.01, 0.99);
        old.srcY = (old.srcY + dy).clamp(0.01, 0.99);
        widget.onSpotsChanged(spots);
      }
      return;
    }

    // 4. Before/After 분할선 이동
    if (_draggingSplit) {
      final norm = _localToImageNorm(pos, imgRect);
      if (norm != null) {
        widget.onSplitPositionChanged(norm.dx.clamp(0.05, 0.95));
      }
      return;
    }

    // 5. 기본 팬(Pan) 이동
    setState(() {
      _pan += details.focalPointDelta;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_isPinching &&
        widget.horizonMode &&
        _horizonStart != null &&
        _horizonEnd != null) {
      final dx = _horizonEnd!.dx - _horizonStart!.dx;
      final dy = _horizonEnd!.dy - _horizonStart!.dy;
      if (math.sqrt(dx * dx + dy * dy) > 12.0) {
        double deg = -math.atan2(dy, dx) * 180.0 / math.pi;
        if (deg > 45.0) deg -= 90.0;
        if (deg < -45.0) deg += 90.0;
        widget.onHorizonAngleComputed(deg.clamp(-45.0, 45.0));
      }
      setState(() {
        _horizonStart = null;
        _horizonEnd = null;
      });
    }
    _isPinching = false;
    _draggingSplit = false;
    _cropDragHandle = null;
    _cropDragStartNorm = null;
    _cropRectAtStart = null;
    _draggingSpotIndex = null;
  }

  MouseCursor _resolveCursor() {
    if (widget.wbPickerMode || widget.horizonMode || widget.spotEditMode) {
      return SystemMouseCursors.precise;
    }
    if (widget.cropEditMode) {
      return SystemMouseCursors.move;
    }
    return SystemMouseCursors.basic;
  }

  @override
  Widget build(BuildContext context) {
    // 이미지가 로드되지 않은 초기 상태: 이상한 물결 이미지 없이 깔끔한 안내 화면 표시 (작은 창 크기에서도 오버플로우 없도록 SingleChildScrollView 적용)
    if (widget.processedImage == null) {
      return Container(
        color: const Color(0xFF141414),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF333333), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.camera_enhance_outlined,
                  size: 46,
                  color: Color(0xFFE8A838),
                ),
                const SizedBox(height: 12),
                const Text(
                  '사진 또는 RAW 파일을 불러오세요',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFEAEAEA),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '지원 포맷: Sony ARW, Canon CR2/CR3, Nikon NEF, DNG, RAF, ORF, RW2, PEF\n및 JPEG, PNG, TIFF, WebP, BMP (드래그 앤 드롭 지원)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF999999),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: widget.onOpenFileRequested,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('📂 사진 파일 열기 (Ctrl+O)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8A838),
                    foregroundColor: const Color(0xFF141414),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final imgRect = _computeImageRect(size);

        return MouseRegion(
          cursor: _resolveCursor(),
          child: Listener(
            onPointerSignal: (e) => _onPointerSignal(e, size),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: resetZoom,
              onTapUp: (d) => _onTapUp(d, size),
              onSecondaryTapUp: (d) => _onSecondaryTapUp(d, size),
              onScaleStart: (d) => _onScaleStart(d, size),
              onScaleUpdate: (d) => _onScaleUpdate(d, size),
              onScaleEnd: _onScaleEnd,
              child: Container(
                color: const Color(0xFF141414),
                child: ClipRect(
                  child: CustomPaint(
                    size: size,
                    painter: _ViewportPainter(
                      processedImage: widget.processedImage!,
                      beforeImage: widget.beforeImage,
                      imgRect: imgRect,
                      params: widget.params,
                      showGrid: widget.showGrid,
                      cropEditMode: widget.cropEditMode,
                      horizonStart: _horizonStart,
                      horizonEnd: _horizonEnd,
                      spotEditMode: widget.spotEditMode,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ViewportPainter extends CustomPainter {
  final ui.Image processedImage;
  final ui.Image? beforeImage;
  final Rect imgRect;
  final PipelineParams params;
  final bool showGrid;
  final bool cropEditMode;
  final Offset? horizonStart;
  final Offset? horizonEnd;
  final bool spotEditMode;

  _ViewportPainter({
    required this.processedImage,
    required this.beforeImage,
    required this.imgRect,
    required this.params,
    required this.showGrid,
    required this.cropEditMode,
    required this.horizonStart,
    required this.horizonEnd,
    required this.spotEditMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imgRect.width <= 0 || imgRect.height <= 0) return;

    final srcRect = Rect.fromLTWH(
      0,
      0,
      processedImage.width.toDouble(),
      processedImage.height.toDouble(),
    );
    final paint = Paint()..filterQuality = FilterQuality.medium;

    // 1. 처리된 결과 이미지 그리기
    canvas.drawImageRect(processedImage, srcRect, imgRect, paint);

    // 2. Before/After 분할 비교 뷰
    if (params.splitViewEnabled && beforeImage != null) {
      final splitX = imgRect.left + params.splitPosition * imgRect.width;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(imgRect.left, imgRect.top, splitX, imgRect.bottom),
      );
      final beforeSrc = Rect.fromLTWH(
        0,
        0,
        beforeImage!.width.toDouble(),
        beforeImage!.height.toDouble(),
      );
      canvas.drawImageRect(beforeImage!, beforeSrc, imgRect, paint);
      canvas.restore();

      // 분할 경계선 및 핸들
      canvas.drawLine(
        Offset(splitX, imgRect.top),
        Offset(splitX, imgRect.bottom),
        Paint()
          ..color = const Color(0xFFE8A838)
          ..strokeWidth = 2.0,
      );
      canvas.drawCircle(
        Offset(splitX, imgRect.center.dy),
        10.0,
        Paint()..color = const Color(0xFFE8A838),
      );

      _drawBadge(canvas, Offset(imgRect.left + 8, imgRect.top + 8), 'BEFORE');
      _drawBadge(canvas, Offset(splitX + 8, imgRect.top + 8), 'AFTER');
    }

    // 3. 3x3 구도 격자선 오버레이
    if (showGrid || cropEditMode || horizonStart != null) {
      final gridPaint = Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 1.0;
      for (int i = 1; i < 3; i++) {
        final gx = imgRect.left + imgRect.width * (i / 3.0);
        final gy = imgRect.top + imgRect.height * (i / 3.0);
        canvas.drawLine(
          Offset(gx, imgRect.top),
          Offset(gx, imgRect.bottom),
          gridPaint,
        );
        canvas.drawLine(
          Offset(imgRect.left, gy),
          Offset(imgRect.right, gy),
          gridPaint,
        );
      }
    }

    // 4. 크롭 편집 오버레이 (cropRect = [x, y, w, h])
    if (cropEditMode) {
      final c = params.cropRect;
      final cropBox = Rect.fromLTWH(
        imgRect.left + c[0] * imgRect.width,
        imgRect.top + c[1] * imgRect.height,
        c[2] * imgRect.width,
        c[3] * imgRect.height,
      );

      // 바깥 어두운 마스크
      final dimPath = Path()
        ..addRect(imgRect)
        ..addRect(cropBox)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(dimPath, Paint()..color = const Color(0x99000000));

      // 크롭 테두리 및 3x3 내부 가이드
      canvas.drawRect(
        cropBox,
        Paint()
          ..color = const Color(0xFFE8A838)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );

      // 4개 모서리 핸들
      final handlePaint = Paint()..color = const Color(0xFFE8A838);
      for (final corner in [
        cropBox.topLeft,
        cropBox.topRight,
        cropBox.bottomLeft,
        cropBox.bottomRight,
      ]) {
        canvas.drawCircle(corner, 6.0, handlePaint);
      }
    }

    // 5. 수평선 2점 드래그 선 표시
    if (horizonStart != null && horizonEnd != null) {
      canvas.drawLine(
        horizonStart!,
        horizonEnd!,
        Paint()
          ..color = const Color(0xFF44FF88)
          ..strokeWidth = 2.5,
      );
      canvas.drawCircle(
        horizonStart!,
        5.0,
        Paint()..color = const Color(0xFF44FF88),
      );
      canvas.drawCircle(
        horizonEnd!,
        5.0,
        Paint()..color = const Color(0xFF44FF88),
      );
    }

    // 6. 잡티 제거(Spot Removal) 원 오버레이
    if (spotEditMode && params.spots.isNotEmpty) {
      final maxDim = math.max(imgRect.width, imgRect.height);
      for (final s in params.spots) {
        final targetPt = Offset(
          imgRect.left + s.x * imgRect.width,
          imgRect.top + s.y * imgRect.height,
        );
        final srcPt = Offset(
          imgRect.left + s.srcX * imgRect.width,
          imgRect.top + s.srcY * imgRect.height,
        );
        final rPx = math.max(6.0, s.r * maxDim);

        canvas.drawLine(
          srcPt,
          targetPt,
          Paint()
            ..color = const Color(0xAA44DDFF)
            ..strokeWidth = 1.2,
        );
        canvas.drawCircle(
          targetPt,
          rPx,
          Paint()
            ..color = const Color(0xFFE8A838)
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(
          srcPt,
          rPx,
          Paint()
            ..color = const Color(0xAA44DDFF)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  void _drawBadge(Canvas canvas, Offset topLeft, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(topLeft.dx, topLeft.dy, tp.width + 10, tp.height + 6),
      const Radius.circular(4),
    );
    canvas.drawRRect(bgRect, Paint()..color = const Color(0xAA000000));
    tp.paint(canvas, Offset(topLeft.dx + 5, topLeft.dy + 3));
  }

  @override
  bool shouldRepaint(covariant _ViewportPainter oldDelegate) => true;
}
