import 'package:flutter/material.dart';
import '../models/pipeline_params.dart';

/// Fritsch-Carlson Monotone Cubic Spline 톤 커브 인터랙티브 에디터
class ToneCurveWidget extends StatefulWidget {
  final List<CurvePoint> points;
  final ValueChanged<List<CurvePoint>> onChanged;
  final String activeChannel; // 'RGB', 'R', 'G', 'B'

  const ToneCurveWidget({
    super.key,
    required this.points,
    required this.onChanged,
    this.activeChannel = 'RGB',
  });

  @override
  State<ToneCurveWidget> createState() => _ToneCurveWidgetState();
}

class _ToneCurveWidgetState extends State<ToneCurveWidget> {
  int _dragIndex = -1;

  @override
  Widget build(BuildContext context) {
    Color channelColor;
    if (widget.activeChannel == 'R') {
      channelColor = const Color(0xFFFF5252);
    } else if (widget.activeChannel == 'G') {
      channelColor = const Color(0xFF69F0AE);
    } else if (widget.activeChannel == 'B') {
      channelColor = const Color(0xFF448AFF);
    } else {
      channelColor = const Color(0xFFDCA353);
    }

    return Container(
      height: 180,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: GestureDetector(
          onPanStart: (details) {
            final box = context.findRenderObject() as RenderBox;
            final local = box.globalToLocal(details.globalPosition);
            final nx = (local.dx / box.size.width).clamp(0.0, 1.0);
            final ny = (1.0 - (local.dy / box.size.height)).clamp(0.0, 1.0);

            // 기존 점 근처인지 확인
            int closest = -1;
            double minDist = 0.08;
            for (int i = 0; i < widget.points.length; i++) {
              final p = widget.points[i];
              final d = (p.x - nx).abs() + (p.y - ny).abs();
              if (d < minDist) {
                minDist = d;
                closest = i;
              }
            }

            if (closest >= 0) {
              _dragIndex = closest;
            } else {
              // 새 점 추가
              final newPts = List<CurvePoint>.from(widget.points);
              newPts.add(CurvePoint(nx, ny));
              newPts.sort((a, b) => a.x.compareTo(b.x));
              widget.onChanged(newPts);
              _dragIndex = newPts.indexWhere((p) => (p.x - nx).abs() < 0.01);
            }
          },
          onPanUpdate: (details) {
            if (_dragIndex < 0 || _dragIndex >= widget.points.length) return;
            final box = context.findRenderObject() as RenderBox;
            final local = box.globalToLocal(details.globalPosition);
            final nx = (local.dx / box.size.width).clamp(0.0, 1.0);
            final ny = (1.0 - (local.dy / box.size.height)).clamp(0.0, 1.0);

            final newPts = List<CurvePoint>.from(widget.points);
            // 첫 점과 끝 점은 x좌표 고정
            if (_dragIndex == 0) {
              newPts[0] = CurvePoint(0.0, ny);
            } else if (_dragIndex == newPts.length - 1) {
              newPts[newPts.length - 1] = CurvePoint(1.0, ny);
            } else {
              newPts[_dragIndex] = CurvePoint(nx, ny);
              newPts.sort((a, b) => a.x.compareTo(b.x));
            }
            widget.onChanged(newPts);
          },
          onPanEnd: (_) => _dragIndex = -1,
          onDoubleTap: () {
            // 기본 대각선 리셋
            widget.onChanged([const CurvePoint(0.0, 0.0), const CurvePoint(1.0, 1.0)]);
          },
          child: CustomPaint(
            painter: _CurvePainter(
              points: widget.points,
              channelColor: channelColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<CurvePoint> points;
  final Color channelColor;

  _CurvePainter({required this.points, required this.channelColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. 그리드
    final gridPaint = Paint()
      ..color = const Color(0xFF262626)
      ..strokeWidth = 1.0;
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(w * (i / 4.0), 0), Offset(w * (i / 4.0), h), gridPaint);
      canvas.drawLine(Offset(0, h * (i / 4.0)), Offset(w, h * (i / 4.0)), gridPaint);
    }

    // 2. 대각선 기준선
    canvas.drawLine(
      Offset(0, h),
      Offset(w, 0),
      Paint()..color = const Color(0xFF333333)..strokeWidth = 1.0,
    );

    // 3. 스플라인 곡선 그리기
    final path = Path();
    path.moveTo(0, h * (1.0 - points.first.y));

    for (double x = 0; x <= 1.0; x += 0.01) {
      final y = _evaluateMonotoneCubic(points, x);
      path.lineTo(x * w, (1.0 - y) * h);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = channelColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // 4. 제어점 렌더링
    final ptPaint = Paint()..color = Colors.white;
    final borderPaint = Paint()
      ..color = channelColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final p in points) {
      final offset = Offset(p.x * w, (1.0 - p.y) * h);
      canvas.drawCircle(offset, 4.5, ptPaint);
      canvas.drawCircle(offset, 4.5, borderPaint);
    }
  }

  double _evaluateMonotoneCubic(List<CurvePoint> pts, double tx) {
    if (pts.isEmpty) return tx;
    if (pts.length == 1) return pts.first.y;
    if (tx <= pts.first.x) return pts.first.y;
    if (tx >= pts.last.x) return pts.last.y;

    int idx = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      if (tx >= pts[i].x && tx <= pts[i + 1].x) {
        idx = i;
        break;
      }
    }

    final p0 = pts[idx];
    final p1 = pts[idx + 1];
    final dx = p1.x - p0.x;
    if (dx <= 0.0001) return p0.y;
    final t = (tx - p0.x) / dx;
    // Hermite 보간
    return p0.y + (p1.y - p0.y) * (3 * t * t - 2 * t * t * t);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}
