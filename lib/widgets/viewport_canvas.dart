import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/pipeline_params.dart';
import '../models/liquify_params.dart';

/// SemiDarktable의 GLImageViewport 인터랙션 및 오버레이 1:1 이식
/// - BMP 재인코딩 없이 GPU 텍스처(ui.Image)를 직접 CustomPainter로 렌더링하여 창 크기 조절 시 크래시/멈춤 원천 차단
/// - 빈 화면 상태 제공 (이상한 물결 샘플 이미지 완전 제거)
/// - Before/After 분할 비교 뷰 (드래그 가능한 분할선)
/// - 3x3 구도 격자 오버레이 (G)
/// - 인터랙티브 크롭 박스 편집 모드 (모서리/변/내부 드래그 및 화면비 고정 지원)
/// - 2점 수평선 그리기 모드 (두 점 드래그로 기울기 각도 자동 계산)
/// - 화이트밸런스 스포이드 모드 (클릭 지점 뉴트럴 픽셀 샘플링)
/// - 스팟 리무버(Spot Remover) 브러시 미리보기, 칠하기(브러시 스트로크), 타겟/소스 개별 이동 및 우클릭 삭제
/// - 적목 제거(Red-Eye) 브러시 미리보기 및 클릭/드래그 보정 모드
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
  final int? selectedSpotIndex;
  final ValueChanged<int?>? onSelectedSpotChanged;
  final (double, double) Function(
    double tx,
    double ty,
    double r,
    List<List<double>> path,
  )? onResolveSmartSpotSource;
  final bool redEyeEditMode;
  final double newRedEyeRadius;
  final double newRedEyeStrength;
  final ValueChanged<List<RedEyeSpot>>? onRedEyesChanged;
  final VoidCallback onOpenFileRequested;
  final ValueChanged<double> onSplitPositionChanged;
  final ValueChanged<List<double>> onCropRectChanged;
  final ValueChanged<double> onHorizonAngleComputed;
  final void Function(double normX, double normY) onWbSamplePicked;
  final ValueChanged<List<Spot>> onSpotsChanged;
  final bool liquifyEditMode;
  final void Function(
    double normX,
    double normY,
    double normDeltaX,
    double normDeltaY,
    double normRadius,
    double pressure,
  )? onLiquifyBrushStroke;
  final VoidCallback? onLiquifyStrokeEnd;
  final ValueChanged<FaceLandmarks>? onFaceLandmarksChanged;

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
    this.selectedSpotIndex,
    this.onSelectedSpotChanged,
    this.onResolveSmartSpotSource,
    this.redEyeEditMode = false,
    this.newRedEyeRadius = 0.025,
    this.newRedEyeStrength = 0.85,
    this.onRedEyesChanged,
    this.liquifyEditMode = false,
    this.onLiquifyBrushStroke,
    this.onLiquifyStrokeEnd,
    this.onFaceLandmarksChanged,
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
  String? _spotDragPart; // 'target', 'source', 'stroke'
  Offset? _spotDragLastNorm;
  final List<Offset> _activeStrokeNorm = [];

  int? _draggingRedEyeIndex;

  bool _isLiquifyBrushing = false;
  Offset? _lastLiquifyNorm;
  String? _draggingFaceAnchor;

  bool _isMiddleMousePanning = false;
  Offset? _hoverLocalPos;
  bool _showRadiusGuide = false;
  Timer? _radiusGuideTimer;

  @override
  void didUpdateWidget(covariant ViewportCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 브러시 크기 슬라이더를 조절할 때 화면 중앙(또는 선택된 스팟)에 브러시 크기를 즉시 가늠할 수 있도록 가이드 원 표시
    if ((widget.spotEditMode &&
            (widget.newSpotRadius - oldWidget.newSpotRadius).abs() > 1e-5) ||
        (widget.redEyeEditMode &&
            (widget.newRedEyeRadius - oldWidget.newRedEyeRadius).abs() >
                1e-5)) {
      _showRadiusGuide = true;
      _radiusGuideTimer?.cancel();
      _radiusGuideTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() => _showRadiusGuide = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _radiusGuideTimer?.cancel();
    super.dispose();
  }

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

  (double, double) _resolveSmartSource(
    double tx,
    double ty,
    double r, [
    List<List<double>> path = const [],
  ]) {
    if (widget.onResolveSmartSpotSource != null) {
      return widget.onResolveSmartSpotSource!(tx, ty, r, path);
    }
    final offsetNorm = (r * 2.4).clamp(0.025, 0.16);
    final srcX = (tx + offsetNorm <= 0.96)
        ? tx + offsetNorm
        : tx - offsetNorm;
    return (srcX.clamp(0.02, 0.98), ty.clamp(0.02, 0.98));
  }

  /// 화면 좌표 pos가 특정 스팟(단일 원 또는 브러시 스트로크 경로)의 타겟 또는 소스 영역 안에 있는지 판정
  bool _hitTestSpotShape(
    Offset pos,
    Rect imgRect,
    Spot s, {
    required bool isSource,
  }) {
    final maxDim = math.max(imgRect.width, imgRect.height);
    final hitR = math.max(16.0, s.r * maxDim + 5.0);
    final offX = isSource ? (s.srcX - s.x) : 0.0;
    final offY = isSource ? (s.srcY - s.y) : 0.0;

    final anchor = Offset(
      imgRect.left + (s.x + offX) * imgRect.width,
      imgRect.top + (s.y + offY) * imgRect.height,
    );
    if ((anchor - pos).distance <= hitR) return true;

    if (s.path.length >= 2) {
      for (int k = 0; k < s.path.length - 1; k++) {
        final a = Offset(
          imgRect.left + (s.path[k][0] + offX) * imgRect.width,
          imgRect.top + (s.path[k][1] + offY) * imgRect.height,
        );
        final b = Offset(
          imgRect.left + (s.path[k + 1][0] + offX) * imgRect.width,
          imgRect.top + (s.path[k + 1][1] + offY) * imgRect.height,
        );
        if (_distToSeg(pos, a, b) <= hitR) return true;
      }
    }
    return false;
  }

  double _distToSeg(Offset p, Offset a, Offset b) {
    final vx = b.dx - a.dx;
    final vy = b.dy - a.dy;
    final wx = p.dx - a.dx;
    final wy = p.dy - a.dy;
    final c1 = wx * vx + wy * vy;
    if (c1 <= 0.0) return (p - a).distance;
    final c2 = vx * vx + vy * vy;
    if (c2 <= c1) return (p - b).distance;
    final t = c1 / c2;
    final proj = Offset(a.dx + t * vx, a.dy + t * vy);
    return (p - proj).distance;
  }

  void _onTapUp(TapUpDetails details, Size size) {
    if (_isMiddleMousePanning) return;
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

    final maxDim = math.max(imgRect.width, imgRect.height);

    // 2. 스팟 리무버(Spot Remover) 클릭 선택 또는 새 단일 스팟 추가
    if (widget.spotEditMode) {
      final spots = widget.params.spots.map((s) => s.clone()).toList();
      for (int i = spots.length - 1; i >= 0; i--) {
        final s = spots[i];
        if (_hitTestSpotShape(details.localPosition, imgRect, s, isSource: true) ||
            _hitTestSpotShape(details.localPosition, imgRect, s, isSource: false)) {
          widget.onSelectedSpotChanged?.call(i);
          return;
        }
      }
      final r = widget.newSpotRadius;
      final src = _resolveSmartSource(norm.dx, norm.dy, r);
      spots.add(
        Spot(
          x: norm.dx,
          y: norm.dy,
          srcX: src.$1,
          srcY: src.$2,
          r: r,
        ),
      );
      widget.onSelectedSpotChanged?.call(spots.length - 1);
      widget.onSpotsChanged(spots);
      return;
    }

    // 3. 적목 제거(Red-Eye) 클릭 추가
    if (widget.redEyeEditMode && widget.onRedEyesChanged != null) {
      final redEyes = widget.params.redEyes.map((e) => e.clone()).toList();
      for (int i = redEyes.length - 1; i >= 0; i--) {
        final re = redEyes[i];
        final hitR = math.max(16.0, re.r * maxDim + 4.0);
        final cx = imgRect.left + re.x * imgRect.width;
        final cy = imgRect.top + re.y * imgRect.height;
        if ((Offset(cx, cy) - details.localPosition).distance <= hitR) {
          return;
        }
      }
      redEyes.add(
        RedEyeSpot(
          x: norm.dx,
          y: norm.dy,
          r: widget.newRedEyeRadius,
          strength: widget.newRedEyeStrength,
        ),
      );
      widget.onRedEyesChanged!(redEyes);
    }
  }

  void _onSecondaryTapUp(TapUpDetails details, Size size) {
    if (widget.processedImage == null) return;
    final imgRect = _computeImageRect(size);
    final maxDim = math.max(imgRect.width, imgRect.height);

    // 우클릭 시 해당 위치의 스팟 리무버 포인트/스트로크 삭제
    if (widget.spotEditMode) {
      final spots = widget.params.spots.map((s) => s.clone()).toList();
      for (int i = spots.length - 1; i >= 0; i--) {
        if (_hitTestSpotShape(details.localPosition, imgRect, spots[i], isSource: true) ||
            _hitTestSpotShape(details.localPosition, imgRect, spots[i], isSource: false)) {
          spots.removeAt(i);
          widget.onSelectedSpotChanged?.call(
            spots.isEmpty ? null : spots.length - 1,
          );
          widget.onSpotsChanged(spots);
          return;
        }
      }
    }

    // 우클릭 시 해당 위치의 적목 제거 포인트 삭제
    if (widget.redEyeEditMode && widget.onRedEyesChanged != null) {
      final redEyes = widget.params.redEyes.map((e) => e.clone()).toList();
      for (int i = redEyes.length - 1; i >= 0; i--) {
        final hitR = math.max(18.0, redEyes[i].r * maxDim + 6.0);
        final cx = imgRect.left + redEyes[i].x * imgRect.width;
        final cy = imgRect.top + redEyes[i].y * imgRect.height;
        if ((Offset(cx, cy) - details.localPosition).distance <= hitR) {
          redEyes.removeAt(i);
          widget.onRedEyesChanged!(redEyes);
          return;
        }
      }
    }
  }

  void _onScaleStart(ScaleStartDetails details, Size size) {
    // 마우스 휠 클릭(중간 버튼) 드래그 중에는 스팟 선택/생성을 하지 않고 화면 팬(Pan)만 수행
    if (_isMiddleMousePanning) return;
    final img = widget.processedImage;
    if (img == null) return;
    _scaleStartZoom = _zoom;

    // 두 손가락 이상(핀치 줌) 시작 시 편집 드래그 모드를 해제하고 확대/축소에 집중
    if (details.pointerCount >= 2) {
      _isPinching = true;
      _draggingSplit = false;
      _cropDragHandle = null;
      _draggingSpotIndex = null;
      _spotDragPart = null;
      _activeStrokeNorm.clear();
      _draggingRedEyeIndex = null;
      _horizonStart = null;
      _horizonEnd = null;
      return;
    }

    _isPinching = false;

    final imgRect = _computeImageRect(size);
    final pos = details.localFocalPoint;
    setState(() => _hoverLocalPos = pos);

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

    final maxDim = math.max(imgRect.width, imgRect.height);

    // 3. 스팟 리무버: 기존 타겟/소스 모양 개별 드래그 또는 빈 곳 브러시 스트로크 그리기 시작
    if (widget.spotEditMode) {
      final norm = _localToImageNorm(pos, imgRect);
      if (norm == null) return;
      final spots = widget.params.spots;
      final order = <int>[
        if (widget.selectedSpotIndex != null &&
            widget.selectedSpotIndex! >= 0 &&
            widget.selectedSpotIndex! < spots.length)
          widget.selectedSpotIndex!,
        for (int i = spots.length - 1; i >= 0; i--)
          if (i != widget.selectedSpotIndex) i,
      ];

      for (final i in order) {
        final s = spots[i];
        // 소스(덮을 위치, 파란 모양) 먼저 히트 테스트
        if (_hitTestSpotShape(pos, imgRect, s, isSource: true)) {
          _draggingSpotIndex = i;
          _spotDragPart = 'source';
          _spotDragLastNorm = norm;
          widget.onSelectedSpotChanged?.call(i);
          return;
        }
        // 타겟(내가 찍은 스팟 위치, 주황 모양) 히트 테스트
        if (_hitTestSpotShape(pos, imgRect, s, isSource: false)) {
          _draggingSpotIndex = i;
          _spotDragPart = 'target';
          _spotDragLastNorm = norm;
          widget.onSelectedSpotChanged?.call(i);
          return;
        }
      }

      // 빈 영역에서 드래그 시작 시: 드래그하는 동안 브러시 모양 궤적을 그리고, 드래그가 끝날 때 하나의 툴로 생성
      setState(() {
        _spotDragPart = 'stroke';
        _draggingSpotIndex = null;
        _activeStrokeNorm
          ..clear()
          ..add(norm);
      });
      return;
    }

    // 4. 적목 제거(Red-Eye) 드래그 이동 또는 새 적목 스팟 브러시 추가
    if (widget.redEyeEditMode && widget.onRedEyesChanged != null) {
      final redEyes = widget.params.redEyes;
      for (int i = redEyes.length - 1; i >= 0; i--) {
        final re = redEyes[i];
        final hitR = math.max(18.0, re.r * maxDim + 6.0);
        final cx = imgRect.left + re.x * imgRect.width;
        final cy = imgRect.top + re.y * imgRect.height;
        if ((Offset(cx, cy) - pos).distance <= hitR) {
          _draggingRedEyeIndex = i;
          return;
        }
      }
      final norm = _localToImageNorm(pos, imgRect);
      if (norm != null) {
        final next = redEyes.map((e) => e.clone()).toList()
          ..add(
            RedEyeSpot(
              x: norm.dx,
              y: norm.dy,
              r: widget.newRedEyeRadius,
              strength: widget.newRedEyeStrength,
            ),
          );
        _draggingRedEyeIndex = next.length - 1;
        widget.onRedEyesChanged!(next);
      }
      return;
    }

    // 4-B. 픽셀 유동화 (Liquify) 브러시 스트로크 및 얼굴 랜드마크 드래그 시작
    if (widget.liquifyEditMode && widget.params.liquifyEnabled) {
      final norm = _localToImageNorm(pos, imgRect);
      if (norm != null) {
        if (widget.params.liquifyTool == LiquifyToolType.faceAware && widget.params.liquifyShowGuide) {
          final lm = widget.params.liquifyLandmarks;
          final anchors = <String, Offset>{
            'leftEye': Offset(lm.leftEyeX, lm.leftEyeY),
            'rightEye': Offset(lm.rightEyeX, lm.rightEyeY),
            'nose': Offset(lm.noseX, lm.noseY),
            'mouth': Offset(lm.mouthX, lm.mouthY),
            'chin': Offset(lm.chinX, lm.chinY),
            'center': Offset(lm.centerX, lm.centerY),
          };
          for (final entry in anchors.entries) {
            final pt = Offset(
              imgRect.left + entry.value.dx * imgRect.width,
              imgRect.top + entry.value.dy * imgRect.height,
            );
            if ((pos - pt).distance <= 22.0) {
              _draggingFaceAnchor = entry.key;
              return;
            }
          }
        }

        if (widget.params.liquifyTool != LiquifyToolType.faceAware) {
          _isLiquifyBrushing = true;
          _lastLiquifyNorm = norm;
          final normR = (widget.params.liquifyBrushSize / maxDim).clamp(0.01, 0.4);
          widget.onLiquifyBrushStroke?.call(
            norm.dx,
            norm.dy,
            0.0,
            0.0,
            normR,
            widget.params.liquifyBrushPressure,
          );
          return;
        }
      }
    }

    // 5. Before/After 분할선 드래그
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
    if (_isMiddleMousePanning) return;
    final img = widget.processedImage;
    if (img == null) return;

    // 두 손가락 핀치 확대/축소 및 팬 이동 처리 (모바일 멀티터치 완벽 지원)
    if (details.pointerCount >= 2 ||
        _isPinching ||
        (details.scale - 1.0).abs() > 1e-3) {
      _isPinching = true;
      setState(() {
        _activeStrokeNorm.clear();
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
    setState(() => _hoverLocalPos = pos);

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

    // 3. 스팟 리무버(Spot Remover): 타겟 이동 / 소스 이동 / 브러시 스트로크 드로잉
    if (widget.spotEditMode) {
      final norm = _localToImageNorm(pos, imgRect);
      if (norm == null) return;

      if (_spotDragPart == 'stroke') {
        if (_activeStrokeNorm.isEmpty ||
            (norm - _activeStrokeNorm.last).distance >= 0.003) {
          setState(() {
            _activeStrokeNorm.add(norm);
          });
        }
        return;
      }

      final spots = widget.params.spots.map((s) => s.clone()).toList();
      if (_draggingSpotIndex != null &&
          _draggingSpotIndex! < spots.length &&
          _spotDragLastNorm != null) {
        final s = spots[_draggingSpotIndex!];
        final dx = norm.dx - _spotDragLastNorm!.dx;
        final dy = norm.dy - _spotDragLastNorm!.dy;
        _spotDragLastNorm = norm;

        if (_spotDragPart == 'target') {
          // 내가 찍은 스팟/스트로크(타겟) 위치만 독립적으로 이동
          s.x = (s.x + dx).clamp(0.01, 0.99);
          s.y = (s.y + dy).clamp(0.01, 0.99);
          for (final pt in s.path) {
            pt[0] = (pt[0] + dx).clamp(0.0, 1.0);
            pt[1] = (pt[1] + dy).clamp(0.0, 1.0);
          }
          widget.onSpotsChanged(spots);
        } else if (_spotDragPart == 'source') {
          // 덮을 위치(소스)만 독립적으로 이동
          s.srcX = (s.srcX + dx).clamp(0.01, 0.99);
          s.srcY = (s.srcY + dy).clamp(0.01, 0.99);
          widget.onSpotsChanged(spots);
        }
      }
      return;
    }

    // 4. 적목 제거(Red-Eye) 이동 (한손가락/좌클릭 드래그 시 화면 이동 차단)
    if (widget.redEyeEditMode) {
      if (_draggingRedEyeIndex != null && widget.onRedEyesChanged != null) {
        final norm = _localToImageNorm(pos, imgRect);
        if (norm != null) {
          final redEyes =
              widget.params.redEyes.map((e) => e.clone()).toList();
          if (_draggingRedEyeIndex! < redEyes.length) {
            redEyes[_draggingRedEyeIndex!].x = norm.dx.clamp(0.01, 0.99);
            redEyes[_draggingRedEyeIndex!].y = norm.dy.clamp(0.01, 0.99);
            widget.onRedEyesChanged!(redEyes);
          }
        }
      }
      return;
    }

    // 4-B. 픽셀 유동화 (Liquify) 브러시 또는 얼굴 랜드마크 드래그 처리
    if (widget.liquifyEditMode && widget.params.liquifyEnabled) {
      final norm = _localToImageNorm(pos, imgRect);
      final maxDim = math.max(imgRect.width, imgRect.height);
      if (norm != null) {
        if (_draggingFaceAnchor != null && widget.onFaceLandmarksChanged != null) {
          final lm = widget.params.liquifyLandmarks.clone();
          switch (_draggingFaceAnchor) {
            case 'leftEye':
              lm.leftEyeX = norm.dx;
              lm.leftEyeY = norm.dy;
              break;
            case 'rightEye':
              lm.rightEyeX = norm.dx;
              lm.rightEyeY = norm.dy;
              break;
            case 'nose':
              lm.noseX = norm.dx;
              lm.noseY = norm.dy;
              break;
            case 'mouth':
              lm.mouthX = norm.dx;
              lm.mouthY = norm.dy;
              break;
            case 'chin':
              lm.chinX = norm.dx;
              lm.chinY = norm.dy;
              break;
            case 'center':
              final ddx = norm.dx - lm.centerX;
              final ddy = norm.dy - lm.centerY;
              lm.centerX = norm.dx;
              lm.centerY = norm.dy;
              lm.leftEyeX = (lm.leftEyeX + ddx).clamp(0.02, 0.98);
              lm.leftEyeY = (lm.leftEyeY + ddy).clamp(0.02, 0.98);
              lm.rightEyeX = (lm.rightEyeX + ddx).clamp(0.02, 0.98);
              lm.rightEyeY = (lm.rightEyeY + ddy).clamp(0.02, 0.98);
              lm.noseX = (lm.noseX + ddx).clamp(0.02, 0.98);
              lm.noseY = (lm.noseY + ddy).clamp(0.02, 0.98);
              lm.mouthX = (lm.mouthX + ddx).clamp(0.02, 0.98);
              lm.mouthY = (lm.mouthY + ddy).clamp(0.02, 0.98);
              lm.chinX = (lm.chinX + ddx).clamp(0.02, 0.98);
              lm.chinY = (lm.chinY + ddy).clamp(0.02, 0.98);
              break;
          }
          widget.onFaceLandmarksChanged!(lm);
          return;
        }

        if (_isLiquifyBrushing && _lastLiquifyNorm != null) {
          final deltaX = norm.dx - _lastLiquifyNorm!.dx;
          final deltaY = norm.dy - _lastLiquifyNorm!.dy;
          _lastLiquifyNorm = norm;
          final normR = (widget.params.liquifyBrushSize / maxDim).clamp(0.01, 0.4);
          widget.onLiquifyBrushStroke?.call(
            norm.dx,
            norm.dy,
            deltaX,
            deltaY,
            normR,
            widget.params.liquifyBrushPressure,
          );
          return;
        }
      }
      return;
    }

    // 5. Before/After 분할선 이동
    if (_draggingSplit) {
      final norm = _localToImageNorm(pos, imgRect);
      if (norm != null) {
        widget.onSplitPositionChanged(norm.dx.clamp(0.05, 0.95));
      }
      return;
    }

    // 6. 기본 팬(Pan) 이동
    setState(() {
      _pan += details.focalPointDelta;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isMiddleMousePanning) return;
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

    // 스팟 리무버 브러시 드래그 종료 시: 그려진 모양 그대로 하나의 스팟 툴로 생성하여 대체!
    if (!_isPinching &&
        widget.spotEditMode &&
        _spotDragPart == 'stroke' &&
        _activeStrokeNorm.isNotEmpty) {
      final strokePts = List<Offset>.from(_activeStrokeNorm);
      setState(() {
        _activeStrokeNorm.clear();
        _spotDragPart = null;
      });

      var sumX = 0.0, sumY = 0.0;
      for (final pt in strokePts) {
        sumX += pt.dx;
        sumY += pt.dy;
      }
      final cx = (sumX / strokePts.length).clamp(0.01, 0.99);
      final cy = (sumY / strokePts.length).clamp(0.01, 0.99);
      final r = widget.newSpotRadius;
      final isMultiPoint = strokePts.length >= 2 &&
          (strokePts.last - strokePts.first).distance > 0.004;
      final strokePath = isMultiPoint
          ? [
              for (final pt in strokePts) [pt.dx, pt.dy],
            ]
          : <List<double>>[];
      final src = _resolveSmartSource(cx, cy, r, strokePath);

      final spots = widget.params.spots.map((s) => s.clone()).toList()
        ..add(
          Spot(
            x: cx,
            y: cy,
            r: r,
            srcX: src.$1,
            srcY: src.$2,
            path: strokePath,
          ),
        );
      widget.onSelectedSpotChanged?.call(spots.length - 1);
      widget.onSpotsChanged(spots);
    }


    if (_isLiquifyBrushing) {
      _isLiquifyBrushing = false;
      _lastLiquifyNorm = null;
      widget.onLiquifyStrokeEnd?.call();
    }
    _draggingFaceAnchor = null;

    _isPinching = false;
    _draggingSplit = false;
    _cropDragHandle = null;
    _cropDragStartNorm = null;
    _cropRectAtStart = null;
    _draggingSpotIndex = null;
    _spotDragPart = null;
    _spotDragLastNorm = null;
    _activeStrokeNorm.clear();
    _draggingRedEyeIndex = null;
  }

  MouseCursor _resolveCursor() {
    if (widget.wbPickerMode ||
        widget.horizonMode ||
        widget.spotEditMode ||
        widget.redEyeEditMode) {
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
          onHover: (e) {
            if (widget.spotEditMode || widget.redEyeEditMode) {
              setState(() => _hoverLocalPos = e.localPosition);
            }
          },
          onExit: (_) {
            if (_hoverLocalPos != null) {
              setState(() => _hoverLocalPos = null);
            }
          },
          child: Listener(
            onPointerSignal: (e) => _onPointerSignal(e, size),
            onPointerDown: (e) {
              // 마우스 휠 클릭(중간 버튼)으로 언제나 자유롭게 화면 드래그(Pan) 가능
              if ((e.buttons & kMiddleMouseButton) != 0) {
                setState(() {
                  _isMiddleMousePanning = true;
                  _activeStrokeNorm.clear();
                });
              }
            },
            onPointerMove: (e) {
              if (_isMiddleMousePanning ||
                  (e.buttons & kMiddleMouseButton) != 0) {
                setState(() {
                  _isMiddleMousePanning = true;
                  _pan += e.delta;
                });
              }
            },
            onPointerUp: (e) {
              if (_isMiddleMousePanning &&
                  (e.buttons & kMiddleMouseButton) == 0) {
                setState(() => _isMiddleMousePanning = false);
              }
            },
            onPointerCancel: (_) {
              if (_isMiddleMousePanning) {
                setState(() => _isMiddleMousePanning = false);
              }
            },
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
                      newSpotRadius: widget.newSpotRadius,
                      selectedSpotIndex: widget.selectedSpotIndex,
                      activeStrokeNorm: List<Offset>.from(_activeStrokeNorm),
                      redEyeEditMode: widget.redEyeEditMode,
                      newRedEyeRadius: widget.newRedEyeRadius,
                      hoverLocalPos: _hoverLocalPos,
                      showRadiusGuide: _showRadiusGuide,
                      liquifyEditMode: widget.liquifyEditMode,
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
  final double newSpotRadius;
  final int? selectedSpotIndex;
  final List<Offset> activeStrokeNorm;
  final bool redEyeEditMode;
  final double newRedEyeRadius;
  final Offset? hoverLocalPos;
  final bool showRadiusGuide;
  final bool liquifyEditMode;

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
    required this.newSpotRadius,
    required this.selectedSpotIndex,
    required this.activeStrokeNorm,
    required this.redEyeEditMode,
    required this.newRedEyeRadius,
    required this.hoverLocalPos,
    required this.showRadiusGuide,
    this.liquifyEditMode = false,
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
    final paint = Paint()..filterQuality = FilterQuality.high;

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

    final maxDim = math.max(imgRect.width, imgRect.height);

    // 6. 스팟 리무버(Spot Remover) 원/브러시 모양 오버레이 및 라이브 브러시 가이드
    if (spotEditMode) {
      for (int i = 0; i < params.spots.length; i++) {
        final s = params.spots[i];
        final isSel = (i == selectedSpotIndex);
        final targetPt = Offset(
          imgRect.left + s.x * imgRect.width,
          imgRect.top + s.y * imgRect.height,
        );
        final srcPt = Offset(
          imgRect.left + s.srcX * imgRect.width,
          imgRect.top + s.srcY * imgRect.height,
        );
        final rPx = math.max(5.0, s.r * maxDim);

        // 소스(파란 모양) ↔ 타겟(주황 모양) 연결선
        canvas.drawLine(
          srcPt,
          targetPt,
          Paint()
            ..color = isSel ? const Color(0xEE55EEFF) : const Color(0x8844DDFF)
            ..strokeWidth = isSel ? 1.8 : 1.2,
        );

        if (s.path.length >= 2) {
          final offX = s.srcX - s.x;
          final offY = s.srcY - s.y;
          final targetScreenPts = <Offset>[
            for (final pt in s.path)
              Offset(
                imgRect.left + pt[0] * imgRect.width,
                imgRect.top + pt[1] * imgRect.height,
              ),
          ];
          final srcScreenPts = <Offset>[
            for (final pt in s.path)
              Offset(
                imgRect.left + (pt[0] + offX) * imgRect.width,
                imgRect.top + (pt[1] + offY) * imgRect.height,
              ),
          ];
          _drawHollowCapsuleStroke(
            canvas,
            targetScreenPts,
            rPx,
            borderColor:
                isSel ? const Color(0xFFFFB838) : const Color(0xCCE8A838),
            fillColor:
                isSel ? const Color(0x28E8A838) : const Color(0x12E8A838),
            borderWidth: isSel ? 2.4 : 1.6,
          );
          _drawHollowCapsuleStroke(
            canvas,
            srcScreenPts,
            rPx,
            borderColor:
                isSel ? const Color(0xFF55EEFF) : const Color(0xAA44DDFF),
            fillColor:
                isSel ? const Color(0x2444DDFF) : const Color(0x1044DDFF),
            borderWidth: isSel ? 2.2 : 1.4,
          );
        } else {
          // 단일 원형 스팟
          if (isSel) {
            canvas.drawCircle(
              targetPt,
              rPx,
              Paint()..color = const Color(0x28E8A838),
            );
          }
          canvas.drawCircle(
            targetPt,
            rPx,
            Paint()
              ..color =
                  isSel ? const Color(0xFFFFB838) : const Color(0xCCE8A838)
              ..strokeWidth = isSel ? 2.4 : 1.6
              ..style = PaintingStyle.stroke,
          );
          if (isSel) {
            canvas.drawCircle(
              srcPt,
              rPx,
              Paint()..color = const Color(0x2444DDFF),
            );
          }
          canvas.drawCircle(
            srcPt,
            rPx,
            Paint()
              ..color =
                  isSel ? const Color(0xFF55EEFF) : const Color(0xAA44DDFF)
              ..strokeWidth = isSel ? 2.2 : 1.3
              ..style = PaintingStyle.stroke,
          );
        }

        // 중심 이동 핸들 점
        canvas.drawCircle(
          targetPt,
          isSel ? 4.2 : 2.8,
          Paint()..color = const Color(0xFFFFB838),
        );
        canvas.drawCircle(
          srcPt,
          isSel ? 4.2 : 2.8,
          Paint()..color = const Color(0xFF55EEFF),
        );
      }

      // 현재 마우스로 드래그하며 그리고 있는 실시간 브러시 모양 표시
      if (activeStrokeNorm.isNotEmpty) {
        final rPx = math.max(5.0, newSpotRadius * maxDim);
        final pts = <Offset>[
          for (final p in activeStrokeNorm)
            Offset(
              imgRect.left + p.dx * imgRect.width,
              imgRect.top + p.dy * imgRect.height,
            ),
        ];
        _drawHollowCapsuleStroke(
          canvas,
          pts,
          rPx,
          borderColor: const Color(0xFFFFD066),
          fillColor: const Color(0x44FFB838),
          borderWidth: 2.2,
        );
      }

      // 브러시 크기 미리보기 원 (마우스 커서 위치 또는 슬라이더 조절 중 화면 중앙)
      final previewCenter = hoverLocalPos ??
          (showRadiusGuide ? imgRect.center : null);
      if (previewCenter != null && imgRect.contains(previewCenter)) {
        final previewR = math.max(4.0, newSpotRadius * maxDim);
        canvas.drawCircle(
          previewCenter,
          previewR,
          Paint()..color = const Color(0x22FFFFFF),
        );
        canvas.drawCircle(
          previewCenter,
          previewR,
          Paint()
            ..color = const Color(0xEEFFFFFF)
            ..strokeWidth = 1.6
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(
          previewCenter,
          previewR,
          Paint()
            ..color = const Color(0xAA000000)
            ..strokeWidth = 0.7
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // 7. 적목 제거(Red-Eye) 원 오버레이 및 라이브 브러시 모양 가이드
    if (redEyeEditMode) {
      for (final re in params.redEyes) {
        final pt = Offset(
          imgRect.left + re.x * imgRect.width,
          imgRect.top + re.y * imgRect.height,
        );
        final rPx = math.max(5.0, re.r * maxDim);
        canvas.drawCircle(
          pt,
          rPx,
          Paint()..color = const Color(0x22FF4444),
        );
        canvas.drawCircle(
          pt,
          rPx,
          Paint()
            ..color = const Color(0xEEFF5555)
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(
          pt,
          3.0,
          Paint()..color = const Color(0xFFFF5555),
        );
      }

      final previewCenter = hoverLocalPos ??
          (showRadiusGuide ? imgRect.center : null);
      if (previewCenter != null && imgRect.contains(previewCenter)) {
        final previewR = math.max(4.0, newRedEyeRadius * maxDim);
        canvas.drawCircle(
          previewCenter,
          previewR,
          Paint()..color = const Color(0x24FF4444),
        );
        canvas.drawCircle(
          previewCenter,
          previewR,
          Paint()
            ..color = const Color(0xEEFF6666)
            ..strokeWidth = 1.6
            ..style = PaintingStyle.stroke,
        );
      }

    // 8. 픽셀 유동화 (Liquify) 브러시 원 및 얼굴 인식 가이드 오버레이
    if (liquifyEditMode && params.liquifyEnabled) {
      if (params.liquifyTool == LiquifyToolType.faceAware && params.liquifyShowGuide) {
        final lm = params.liquifyLandmarks;
        final faceCenter = Offset(
          imgRect.left + lm.centerX * imgRect.width,
          imgRect.top + lm.centerY * imgRect.height,
        );
        final faceW = lm.width * imgRect.width;
        final faceH = lm.height * imgRect.height;
        final faceRect = Rect.fromCenter(center: faceCenter, width: faceW, height: faceH);

        canvas.drawOval(
          faceRect,
          Paint()
            ..color = const Color(0x99E8A838)
            ..strokeWidth = 1.6
            ..style = PaintingStyle.stroke,
        );

        final anchors = [
          Offset(imgRect.left + lm.leftEyeX * imgRect.width, imgRect.top + lm.leftEyeY * imgRect.height),
          Offset(imgRect.left + lm.rightEyeX * imgRect.width, imgRect.top + lm.rightEyeY * imgRect.height),
          Offset(imgRect.left + lm.noseX * imgRect.width, imgRect.top + lm.noseY * imgRect.height),
          Offset(imgRect.left + lm.mouthX * imgRect.width, imgRect.top + lm.mouthY * imgRect.height),
          Offset(imgRect.left + lm.chinX * imgRect.width, imgRect.top + lm.chinY * imgRect.height),
        ];
        for (final pt in anchors) {
          canvas.drawCircle(pt, 5.5, Paint()..color = const Color(0xFFE8A838));
          canvas.drawCircle(pt, 5.5, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1.0);
        }
      } else if (params.liquifyTool != LiquifyToolType.faceAware) {
        final previewCenter = hoverLocalPos ?? imgRect.center;
        if (imgRect.contains(previewCenter)) {
          final previewR = math.max(4.0, (params.liquifyBrushSize / maxDim) * maxDim);
          canvas.drawCircle(previewCenter, previewR, Paint()..color = const Color(0x2200E5FF));
          canvas.drawCircle(
            previewCenter,
            previewR,
            Paint()
              ..color = const Color(0xEE00E5FF)
              ..strokeWidth = 1.6
              ..style = PaintingStyle.stroke,
          );
        }
      }
    }
    }
  }

  /// 브러시로 드래그한 궤적(pts)을 내부 겹침선 없이 깔끔한 단일 캡슐 테두리 모양으로 렌더링
  void _drawHollowCapsuleStroke(
    Canvas canvas,
    List<Offset> pts,
    double rPx, {
    required Color borderColor,
    required Color fillColor,
    required double borderWidth,
  }) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, rPx, Paint()..color = fillColor);
      canvas.drawCircle(
        pts.first,
        rPx,
        Paint()
          ..color = borderColor
          ..strokeWidth = borderWidth
          ..style = PaintingStyle.stroke,
      );
      return;
    }

    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final p = pts[i];
      path.lineTo(p.dx, p.dy);
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final pad = rPx + borderWidth + 4.0;
    final bounds = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);

    // 1. 반투명 내부 채움 레이어
    canvas.saveLayer(bounds, Paint());
    canvas.drawPath(
      path,
      Paint()
        ..color = fillColor
        ..strokeWidth = rPx * 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();

    // 2. 외곽선만 남기는 중공(Hollow) 캡슐 테두리 레이어
    canvas.saveLayer(bounds, Paint());
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..strokeWidth = rPx * 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    final innerDiameter = math.max(0.0, rPx * 2.0 - borderWidth * 2.0);
    if (innerDiameter > 0.5) {
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.clear
          ..strokeWidth = innerDiameter
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
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
