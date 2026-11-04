import 'dart:math' as math;
import 'dart:typed_data';

/// 포토샵 리퀴파이(Liquify) 도구 종류 (포토샵 CC 2018 REA 분석 기준)
enum LiquifyToolType {
  warp, // 뒤틀기 (Forward Warp)
  reconstruct, // 재구성 (Reconstruct)
  smooth, // 매끄럽게 (Smooth)
  twirlCW, // 시계 방향 회전 (Twirl Clockwise)
  twirlCCW, // 반시계 방향 회전 (Twirl Counterclockwise)
  pucker, // 오목 (Pucker)
  bloat, // 볼록 (Bloat)
  pushLeft, // 왼쪽 밀기 (Push Left)
  faceAware, // 얼굴 인식 조정 (Face-Aware)
}

/// 사진 내 감지되거나 수동 조절된 얼굴 앵커 랜드마크 (0~1 정규화 좌표)
class FaceLandmarks {
  double centerX;
  double centerY;
  double width;
  double height;

  double leftEyeX;
  double leftEyeY;
  double rightEyeX;
  double rightEyeY;

  double noseX;
  double noseY;
  double mouthX;
  double mouthY;
  double chinX;
  double chinY;

  FaceLandmarks({
    this.centerX = 0.5,
    this.centerY = 0.42,
    this.width = 0.32,
    this.height = 0.42,
    this.leftEyeX = 0.41,
    this.leftEyeY = 0.38,
    this.rightEyeX = 0.59,
    this.rightEyeY = 0.38,
    this.noseX = 0.50,
    this.noseY = 0.45,
    this.mouthX = 0.50,
    this.mouthY = 0.55,
    this.chinX = 0.50,
    this.chinY = 0.65,
  });

  FaceLandmarks clone() => FaceLandmarks(
        centerX: centerX,
        centerY: centerY,
        width: width,
        height: height,
        leftEyeX: leftEyeX,
        leftEyeY: leftEyeY,
        rightEyeX: rightEyeX,
        rightEyeY: rightEyeY,
        noseX: noseX,
        noseY: noseY,
        mouthX: mouthX,
        mouthY: mouthY,
        chinX: chinX,
        chinY: chinY,
      );

  Map<String, dynamic> toMap() => {
        'centerX': centerX,
        'centerY': centerY,
        'width': width,
        'height': height,
        'leftEyeX': leftEyeX,
        'leftEyeY': leftEyeY,
        'rightEyeX': rightEyeX,
        'rightEyeY': rightEyeY,
        'noseX': noseX,
        'noseY': noseY,
        'mouthX': mouthX,
        'mouthY': mouthY,
        'chinX': chinX,
        'chinY': chinY,
      };

  factory FaceLandmarks.fromMap(Map m) {
    double d(dynamic v, double def) => v is num ? v.toDouble() : def;
    return FaceLandmarks(
      centerX: d(m['centerX'], 0.5),
      centerY: d(m['centerY'], 0.42),
      width: d(m['width'], 0.32),
      height: d(m['height'], 0.42),
      leftEyeX: d(m['leftEyeX'], 0.41),
      leftEyeY: d(m['leftEyeY'], 0.38),
      rightEyeX: d(m['rightEyeX'], 0.59),
      rightEyeY: d(m['rightEyeY'], 0.38),
      noseX: d(m['noseX'], 0.50),
      noseY: d(m['noseY'], 0.45),
      mouthX: d(m['mouthX'], 0.50),
      mouthY: d(m['mouthY'], 0.55),
      chinX: d(m['chinX'], 0.50),
      chinY: d(m['chinY'], 0.65),
    );
  }
}

/// 포토샵 CC 2018 얼굴 인식 유동화(Face-Aware Liquify) 파라미터 세트 (-100 ~ +100)
class FaceAwareParams {
  // 눈 (Eyes)
  double eyeSizeLeft = 0.0;
  double eyeSizeRight = 0.0;
  bool eyeSizeLink = true;

  double eyeHeightLeft = 0.0;
  double eyeHeightRight = 0.0;
  double eyeWidthLeft = 0.0;
  double eyeWidthRight = 0.0;
  double eyeTiltLeft = 0.0;
  double eyeTiltRight = 0.0;
  double eyeDistance = 0.0;

  // 코 (Nose)
  double noseHeight = 0.0;
  double noseWidth = 0.0;

  // 입 (Mouth)
  double smile = 0.0;
  double upperLip = 0.0;
  double lowerLip = 0.0;
  double mouthWidth = 0.0;
  double mouthHeight = 0.0;

  // 얼굴 모양 (Face Shape)
  double forehead = 0.0;
  double chinHeight = 0.0;
  double jawline = 0.0;
  double faceWidth = 0.0;

  FaceAwareParams();

  bool get isNeutral =>
      eyeSizeLeft.abs() < 0.01 &&
      eyeSizeRight.abs() < 0.01 &&
      eyeHeightLeft.abs() < 0.01 &&
      eyeHeightRight.abs() < 0.01 &&
      eyeWidthLeft.abs() < 0.01 &&
      eyeWidthRight.abs() < 0.01 &&
      eyeTiltLeft.abs() < 0.01 &&
      eyeTiltRight.abs() < 0.01 &&
      eyeDistance.abs() < 0.01 &&
      noseHeight.abs() < 0.01 &&
      noseWidth.abs() < 0.01 &&
      smile.abs() < 0.01 &&
      upperLip.abs() < 0.01 &&
      lowerLip.abs() < 0.01 &&
      mouthWidth.abs() < 0.01 &&
      mouthHeight.abs() < 0.01 &&
      forehead.abs() < 0.01 &&
      chinHeight.abs() < 0.01 &&
      jawline.abs() < 0.01 &&
      faceWidth.abs() < 0.01;

  void reset() {
    eyeSizeLeft = 0.0;
    eyeSizeRight = 0.0;
    eyeSizeLink = true;
    eyeHeightLeft = 0.0;
    eyeHeightRight = 0.0;
    eyeWidthLeft = 0.0;
    eyeWidthRight = 0.0;
    eyeTiltLeft = 0.0;
    eyeTiltRight = 0.0;
    eyeDistance = 0.0;
    noseHeight = 0.0;
    noseWidth = 0.0;
    smile = 0.0;
    upperLip = 0.0;
    lowerLip = 0.0;
    mouthWidth = 0.0;
    mouthHeight = 0.0;
    forehead = 0.0;
    chinHeight = 0.0;
    jawline = 0.0;
    faceWidth = 0.0;
  }

  FaceAwareParams clone() {
    final p = FaceAwareParams();
    p.eyeSizeLeft = eyeSizeLeft;
    p.eyeSizeRight = eyeSizeRight;
    p.eyeSizeLink = eyeSizeLink;
    p.eyeHeightLeft = eyeHeightLeft;
    p.eyeHeightRight = eyeHeightRight;
    p.eyeWidthLeft = eyeWidthLeft;
    p.eyeWidthRight = eyeWidthRight;
    p.eyeTiltLeft = eyeTiltLeft;
    p.eyeTiltRight = eyeTiltRight;
    p.eyeDistance = eyeDistance;
    p.noseHeight = noseHeight;
    p.noseWidth = noseWidth;
    p.smile = smile;
    p.upperLip = upperLip;
    p.lowerLip = lowerLip;
    p.mouthWidth = mouthWidth;
    p.mouthHeight = mouthHeight;
    p.forehead = forehead;
    p.chinHeight = chinHeight;
    p.jawline = jawline;
    p.faceWidth = faceWidth;
    return p;
  }

  Map<String, dynamic> toMap() => {
        'eyeSizeLeft': eyeSizeLeft,
        'eyeSizeRight': eyeSizeRight,
        'eyeSizeLink': eyeSizeLink,
        'eyeHeightLeft': eyeHeightLeft,
        'eyeHeightRight': eyeHeightRight,
        'eyeWidthLeft': eyeWidthLeft,
        'eyeWidthRight': eyeWidthRight,
        'eyeTiltLeft': eyeTiltLeft,
        'eyeTiltRight': eyeTiltRight,
        'eyeDistance': eyeDistance,
        'noseHeight': noseHeight,
        'noseWidth': noseWidth,
        'smile': smile,
        'upperLip': upperLip,
        'lowerLip': lowerLip,
        'mouthWidth': mouthWidth,
        'mouthHeight': mouthHeight,
        'forehead': forehead,
        'chinHeight': chinHeight,
        'jawline': jawline,
        'faceWidth': faceWidth,
      };

  factory FaceAwareParams.fromMap(Map m) {
    double d(dynamic v, double def) => v is num ? v.toDouble() : def;
    final p = FaceAwareParams();
    p.eyeSizeLeft = d(m['eyeSizeLeft'], 0.0);
    p.eyeSizeRight = d(m['eyeSizeRight'], 0.0);
    p.eyeSizeLink = m['eyeSizeLink'] is bool ? m['eyeSizeLink'] : true;
    p.eyeHeightLeft = d(m['eyeHeightLeft'], 0.0);
    p.eyeHeightRight = d(m['eyeHeightRight'], 0.0);
    p.eyeWidthLeft = d(m['eyeWidthLeft'], 0.0);
    p.eyeWidthRight = d(m['eyeWidthRight'], 0.0);
    p.eyeTiltLeft = d(m['eyeTiltLeft'], 0.0);
    p.eyeTiltRight = d(m['eyeTiltRight'], 0.0);
    p.eyeDistance = d(m['eyeDistance'], 0.0);
    p.noseHeight = d(m['noseHeight'], 0.0);
    p.noseWidth = d(m['noseWidth'], 0.0);
    p.smile = d(m['smile'], 0.0);
    p.upperLip = d(m['upperLip'], 0.0);
    p.lowerLip = d(m['lowerLip'], 0.0);
    p.mouthWidth = d(m['mouthWidth'], 0.0);
    p.mouthHeight = d(m['mouthHeight'], 0.0);
    p.forehead = d(m['forehead'], 0.0);
    p.chinHeight = d(m['chinHeight'], 0.0);
    p.jawline = d(m['jawline'], 0.0);
    p.faceWidth = d(m['faceWidth'], 0.0);
    return p;
  }
}

/// 유동화 변위 필드 (Mesh Displacement Grid)
/// 64x64 또는 128x128 2D 격자점의 오프셋 (dx, dy)을 보관하여 브러시 드래그 및 얼굴 인식을 실시간 쌍선형 보간으로 워핑
class LiquifyDisplacementGrid {
  static const int kGridCols = 64;
  static const int kGridRows = 64;

  final Float32List dx;
  final Float32List dy;

  LiquifyDisplacementGrid({Float32List? dx, Float32List? dy})
      : dx = dx ?? Float32List(kGridCols * kGridRows),
        dy = dy ?? Float32List(kGridCols * kGridRows);

  bool get isEmpty {
    for (var i = 0; i < dx.length; i++) {
      if (dx[i] != 0.0 || dy[i] != 0.0) return false;
    }
    return true;
  }

  void clear() {
    dx.fillRange(0, dx.length, 0.0);
    dy.fillRange(0, dy.length, 0.0);
  }

  LiquifyDisplacementGrid clone() {
    return LiquifyDisplacementGrid(
      dx: Float32List.fromList(dx),
      dy: Float32List.fromList(dy),
    );
  }

  /// 브러시 스트로크 적용 (뒤틀기, 볼록, 오목, 회전, 복원, 스무스)
  void applyBrush({
    required LiquifyToolType tool,
    required double normX,
    required double normY,
    required double normRadius,
    required double normDeltaX,
    required double normDeltaY,
    required double pressure,
  }) {
    final rSq = normRadius * normRadius;
    if (rSq <= 1e-7) return;

    final minCol = math.max(0, ((normX - normRadius) * (kGridCols - 1)).floor());
    final maxCol = math.min(kGridCols - 1, ((normX + normRadius) * (kGridCols - 1)).ceil());
    final minRow = math.max(0, ((normY - normRadius) * (kGridRows - 1)).floor());
    final maxRow = math.min(kGridRows - 1, ((normY + normRadius) * (kGridRows - 1)).ceil());

    for (var r = minRow; r <= maxRow; r++) {
      final ny = r / (kGridRows - 1);
      final dyCenter = ny - normY;

      for (var c = minCol; c <= maxCol; c++) {
        final nx = c / (kGridCols - 1);
        final dxCenter = nx - normX;
        final dSq = dxCenter * dxCenter + dyCenter * dyCenter;
        if (dSq >= rSq) continue;

        final dist = math.sqrt(dSq);
        // 부드러운 코사인 가우시안 폴오프
        final falloff = 0.5 * (1.0 + math.cos(math.pi * (dist / normRadius))) * pressure;
        final idx = r * kGridCols + c;

        switch (tool) {
          case LiquifyToolType.warp:
            dx[idx] += (normDeltaX * falloff).clamp(-0.4, 0.4);
            dy[idx] += (normDeltaY * falloff).clamp(-0.4, 0.4);
            break;
          case LiquifyToolType.bloat:
            // 중심에서 바깥쪽으로 밀기
            if (dist > 1e-5) {
              final dirX = dxCenter / dist;
              final dirY = dyCenter / dist;
              final str = normRadius * 0.15 * falloff;
              dx[idx] += dirX * str;
              dy[idx] += dirY * str;
            }
            break;
          case LiquifyToolType.pucker:
            // 중심 쪽으로 당기기
            if (dist > 1e-5) {
              final dirX = dxCenter / dist;
              final dirY = dyCenter / dist;
              final str = normRadius * 0.15 * falloff;
              dx[idx] -= dirX * str;
              dy[idx] -= dirY * str;
            }
            break;
          case LiquifyToolType.twirlCW:
            // 시계 방향 접선 회전
            final angle = 0.6 * falloff;
            final cosA = math.cos(angle);
            final sinA = math.sin(angle);
            final curX = dxCenter + dx[idx];
            final curY = dyCenter + dy[idx];
            final rotX = curX * cosA - curY * sinA;
            final rotY = curX * sinA + curY * cosA;
            dx[idx] = rotX - dxCenter;
            dy[idx] = rotY - dyCenter;
            break;
          case LiquifyToolType.twirlCCW:
            // 반시계 방향 회전
            final angle = -0.6 * falloff;
            final cosA = math.cos(angle);
            final sinA = math.sin(angle);
            final curX = dxCenter + dx[idx];
            final curY = dyCenter + dy[idx];
            final rotX = curX * cosA - curY * sinA;
            final rotY = curX * sinA + curY * cosA;
            dx[idx] = rotX - dxCenter;
            dy[idx] = rotY - dyCenter;
            break;
          case LiquifyToolType.pushLeft:
            // 브러시 진행 방향의 수직 왼쪽으로 밀기
            final len = math.sqrt(normDeltaX * normDeltaX + normDeltaY * normDeltaY);
            if (len > 1e-5) {
              final leftX = -normDeltaY / len * math.min(len * 2.0, normRadius * 0.2);
              final leftY = normDeltaX / len * math.min(len * 2.0, normRadius * 0.2);
              dx[idx] += leftX * falloff;
              dy[idx] += leftY * falloff;
            }
            break;
          case LiquifyToolType.reconstruct:
            // 원래 0으로 복원
            final recFactor = math.max(0.0, 1.0 - falloff * 0.7);
            dx[idx] *= recFactor;
            dy[idx] *= recFactor;
            break;
          case LiquifyToolType.smooth:
            // 주변 이웃 노드와의 평균으로 스무딩
            var avgX = dx[idx];
            var avgY = dy[idx];
            var count = 1;
            if (c > 0) {
              avgX += dx[idx - 1];
              avgY += dy[idx - 1];
              count++;
            }
            if (c < kGridCols - 1) {
              avgX += dx[idx + 1];
              avgY += dy[idx + 1];
              count++;
            }
            if (r > 0) {
              avgX += dx[idx - kGridCols];
              avgY += dy[idx - kGridCols];
              count++;
            }
            if (r < kGridRows - 1) {
              avgX += dx[idx + kGridCols];
              avgY += dy[idx + kGridCols];
              count++;
            }
            avgX /= count;
            avgY /= count;
            final smFactor = (falloff * 0.5).clamp(0.0, 1.0);
            dx[idx] = dx[idx] * (1.0 - smFactor) + avgX * smFactor;
            dy[idx] = dy[idx] * (1.0 - smFactor) + avgY * smFactor;
            break;
          case LiquifyToolType.faceAware:
            break;
        }
      }
    }
  }

  /// 특정 정규화 좌표(0~1)에서의 보간된 오프셋 (dx, dy) 획득
  @pragma('vm:prefer-inline')
  (double, double) sample(double nx, double ny) {
    final cx = (nx * (kGridCols - 1)).clamp(0.0, (kGridCols - 1).toDouble());
    final cy = (ny * (kGridRows - 1)).clamp(0.0, (kGridRows - 1).toDouble());

    final x0 = cx.floor();
    final y0 = cy.floor();
    final x1 = math.min(kGridCols - 1, x0 + 1);
    final y1 = math.min(kGridRows - 1, y0 + 1);

    final fx = cx - x0;
    final fy = cy - y0;

    final i00 = y0 * kGridCols + x0;
    final i10 = y0 * kGridCols + x1;
    final i01 = y1 * kGridCols + x0;
    final i11 = y1 * kGridCols + x1;

    final topX = dx[i00] * (1.0 - fx) + dx[i10] * fx;
    final botX = dx[i01] * (1.0 - fx) + dx[i11] * fx;
    final outDx = topX * (1.0 - fy) + botX * fy;

    final topY = dy[i00] * (1.0 - fx) + dy[i10] * fx;
    final botY = dy[i01] * (1.0 - fx) + dy[i11] * fx;
    final outDy = topY * (1.0 - fy) + botY * fy;

    return (outDx, outDy);
  }

  List<double> toDxList() => dx.toList();
  List<double> toDyList() => dy.toList();

  factory LiquifyDisplacementGrid.fromLists(List? xList, List? yList) {
    final grid = LiquifyDisplacementGrid();
    if (xList is List && yList is List) {
      final len = math.min(grid.dx.length, math.min(xList.length, yList.length));
      for (var i = 0; i < len; i++) {
        final vx = xList[i];
        final vy = yList[i];
        if (vx is num) grid.dx[i] = vx.toDouble();
        if (vy is num) grid.dy[i] = vy.toDouble();
      }
    }
    return grid;
  }
}
