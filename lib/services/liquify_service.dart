import 'dart:math' as math;
import 'dart:typed_data';

import '../models/liquify_params.dart';
import 'pipeline_core.dart';

/// 포토샵 CC 2018 REA 역공학 기반 픽셀 유동화 및 얼굴 인식 워핑 서비스
class LiquifyService {
  /// 프록시 이미지에서 스마트 얼굴 인식(스킨톤 및 눈/코/입 특징점 추출)
  static (bool, FaceLandmarks) detectFace(ProxyImage img) {
    final w = img.width;
    final h = img.height;
    final rgb = img.rgb;

    // 1. 피부색 픽셀 마스크 및 무게중심 계산 (YCbCr 스킨톤 모델)
    var skinCount = 0;
    var sumX = 0.0;
    var sumY = 0.0;
    var minX = w, maxX = 0, minY = h, maxY = 0;

    final stride = math.max(1, (math.min(w, h) / 120).floor());

    for (var y = 0; y < h; y += stride) {
      final rowIdx = y * w;
      for (var x = 0; x < w; x += stride) {
        final pi = (rowIdx + x) * 3;
        final r = rgb[pi];
        final g = rgb[pi + 1];
        final b = rgb[pi + 2];

        // R > G > B 및 R-G > 15 피부색 기본 조건
        if (r > 50 && g > 30 && b > 20 && r > g && g >= b && (r - g) >= 12) {
          // YCbCr 변환 검사
          final yVal = 0.299 * r + 0.587 * g + 0.114 * b;
          final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
          final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;

          if (cr >= 132 && cr <= 175 && cb >= 75 && cb <= 130 && yVal >= 40) {
            skinCount++;
            sumX += x;
            sumY += y;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
    }

    final totalSampled = (w ~/ stride) * (h ~/ stride);
    final skinRatio = skinCount / math.max(1, totalSampled);

    // 피부톤이 일정 수준(3% 이상) 감지되면 해당 영역을 바탕으로 얼굴 추정
    if (skinRatio >= 0.03 && skinCount > 20) {
      final faceCx = (sumX / skinCount) / w;
      final faceCy = (sumY / skinCount) / h;
      final faceW = ((maxX - minX) / w).clamp(0.20, 0.70);
      final faceH = ((maxY - minY) / h).clamp(0.25, 0.85);

      final eyeY = (faceCy - faceH * 0.16).clamp(0.08, 0.90);
      final leftEyeX = (faceCx - faceW * 0.24).clamp(0.05, 0.95);
      final rightEyeX = (faceCx + faceW * 0.24).clamp(0.05, 0.95);
      final noseY = (faceCy + faceH * 0.02).clamp(0.10, 0.92);
      final mouthY = (faceCy + faceH * 0.24).clamp(0.12, 0.95);
      final chinY = (faceCy + faceH * 0.46).clamp(0.15, 0.98);

      return (
        true,
        FaceLandmarks(
          centerX: faceCx,
          centerY: faceCy,
          width: faceW,
          height: faceH,
          leftEyeX: leftEyeX,
          leftEyeY: eyeY,
          rightEyeX: rightEyeX,
          rightEyeY: eyeY,
          noseX: faceCx,
          noseY: noseY,
          mouthX: faceCx,
          mouthY: mouthY,
          chinX: faceCx,
          chinY: chinY,
        )
      );
    }

    // 피부톤 감지 비율이 낮더라도 인물 사진 기본 랜드마크를 제공하여 수동 조절 가능케 함
    return (
      false,
      FaceLandmarks(
        centerX: 0.50,
        centerY: 0.42,
        width: 0.35,
        height: 0.45,
        leftEyeX: 0.41,
        leftEyeY: 0.35,
        rightEyeX: 0.59,
        rightEyeY: 0.35,
        noseX: 0.50,
        noseY: 0.44,
        mouthX: 0.50,
        mouthY: 0.56,
        chinX: 0.50,
        chinY: 0.68,
      )
    );
  }

  /// 포토샵 Face-Aware Liquify 파라미터를 유동화 변위 그리드에 누적 계산
  static void applyFaceAwareToGrid({
    required LiquifyDisplacementGrid grid,
    required FaceLandmarks lm,
    required FaceAwareParams params,
  }) {
    if (params.isNeutral) return;

    final cols = LiquifyDisplacementGrid.kGridCols;
    final rows = LiquifyDisplacementGrid.kGridRows;

    final eyeSizeL = params.eyeSizeLeft / 100.0;
    final eyeSizeR = (params.eyeSizeLink ? params.eyeSizeLeft : params.eyeSizeRight) / 100.0;
    final eyeW_L = params.eyeWidthLeft / 100.0;
    final eyeW_R = params.eyeWidthRight / 100.0;
    final eyeH_L = params.eyeHeightLeft / 100.0;
    final eyeH_R = params.eyeHeightRight / 100.0;
    final eyeTiltL = params.eyeTiltLeft / 100.0;
    final eyeTiltR = params.eyeTiltRight / 100.0;
    final eyeDist = params.eyeDistance / 100.0;

    final noseH = params.noseHeight / 100.0;
    final noseW = params.noseWidth / 100.0;

    final smile = params.smile / 100.0;
    final upLip = params.upperLip / 100.0;
    final lowLip = params.lowerLip / 100.0;
    final mouthW = params.mouthWidth / 100.0;
    final mouthH = params.mouthHeight / 100.0;

    final forehead = params.forehead / 100.0;
    final chinH = params.chinHeight / 100.0;
    final jawline = params.jawline / 100.0;
    final faceW = params.faceWidth / 100.0;

    final eyeRadius = lm.width * 0.22;
    final noseRadius = lm.width * 0.24;
    final mouthRadius = lm.width * 0.28;
    final faceRadius = lm.width * 0.65;

    for (var r = 0; r < rows; r++) {
      final ny = r / (rows - 1);
      final rOffset = r * cols;

      for (var c = 0; c < cols; c++) {
        final nx = c / (cols - 1);
        final idx = rOffset + c;

        // 1. 왼쪽 눈 워핑 (Eye Size, Width, Height, Tilt, Distance)
        {
          final dxL = nx - lm.leftEyeX;
          final dyL = ny - lm.leftEyeY;
          final distSqL = dxL * dxL + dyL * dyL;
          if (distSqL < eyeRadius * eyeRadius) {
            final dist = math.sqrt(distSqL);
            final falloff = 0.5 * (1.0 + math.cos(math.pi * (dist / eyeRadius)));

            // 눈 크기 (스케일)
            final scale = (eyeSizeL * 0.04) * falloff;
            grid.dx[idx] -= dxL * scale;
            grid.dy[idx] -= dyL * scale;

            // 눈 너비/높이
            grid.dx[idx] -= dxL * (eyeW_L * 0.035 * falloff);
            grid.dy[idx] -= dyL * (eyeH_L * 0.035 * falloff);

            // 눈 기울기
            final tiltAng = eyeTiltL * 0.18 * falloff;
            grid.dy[idx] += dxL * tiltAng;

            // 눈 사이 거리 (바깥쪽/안쪽 이동)
            grid.dx[idx] -= (eyeDist * 0.02) * falloff;
          }
        }

        // 2. 오른쪽 눈 워핑
        {
          final dxR = nx - lm.rightEyeX;
          final dyR = ny - lm.rightEyeY;
          final distSqR = dxR * dxR + dyR * dyR;
          if (distSqR < eyeRadius * eyeRadius) {
            final dist = math.sqrt(distSqR);
            final falloff = 0.5 * (1.0 + math.cos(math.pi * (dist / eyeRadius)));

            final scale = (eyeSizeR * 0.04) * falloff;
            grid.dx[idx] -= dxR * scale;
            grid.dy[idx] -= dyR * scale;

            grid.dx[idx] -= dxR * (eyeW_R * 0.035 * falloff);
            grid.dy[idx] -= dyR * (eyeH_R * 0.035 * falloff);

            final tiltAng = -eyeTiltR * 0.18 * falloff;
            grid.dy[idx] += dxR * tiltAng;

            grid.dx[idx] += (eyeDist * 0.02) * falloff;
          }
        }

        // 3. 코 워핑 (Nose Height, Width)
        {
          final dxN = nx - lm.noseX;
          final dyN = ny - lm.noseY;
          final distSqN = dxN * dxN + dyN * dyN;
          if (distSqN < noseRadius * noseRadius) {
            final dist = math.sqrt(distSqN);
            final falloff = 0.5 * (1.0 + math.cos(math.pi * (dist / noseRadius)));

            // 코 너비
            grid.dx[idx] -= dxN * (noseW * 0.05 * falloff);
            // 코 높이 (상하 이동)
            grid.dy[idx] -= (noseH * 0.025 * falloff);
          }
        }

        // 4. 입 워핑 (Smile, UpperLip, LowerLip, Mouth Width, Height)
        {
          final dxM = nx - lm.mouthX;
          final dyM = ny - lm.mouthY;
          final distSqM = dxM * dxM + dyM * dyM;
          if (distSqM < mouthRadius * mouthRadius) {
            final dist = math.sqrt(distSqM);
            final falloff = 0.5 * (1.0 + math.cos(math.pi * (dist / mouthRadius)));

            // 미소 (Smile): 좌우 입꼬리를 위로 당김
            final cornerWeight = (dxM.abs() / (lm.width * 0.15)).clamp(0.0, 1.2);
            grid.dy[idx] -= (smile * 0.03 * cornerWeight * falloff);

            // 윗입술 / 아랫입술 두께
            if (dyM < 0) {
              grid.dy[idx] += (upLip * 0.015 * falloff);
            } else {
              grid.dy[idx] -= (lowLip * 0.015 * falloff);
            }

            // 입 너비 / 높이
            grid.dx[idx] -= dxM * (mouthW * 0.04 * falloff);
            grid.dy[idx] -= dyM * (mouthH * 0.04 * falloff);
          }
        }

        // 5. 얼굴형 (Forehead, Chin Height, Jawline, Face Width)
        {
          final dxF = nx - lm.centerX;
          final dyF = ny - lm.centerY;
          final distSqF = dxF * dxF + dyF * dyF;
          if (distSqF < faceRadius * faceRadius) {
            final dist = math.sqrt(distSqF);
            final falloff = 0.5 * (1.0 + math.cos(math.pi * (dist / faceRadius)));

            // 이마 (상단)
            if (ny < lm.centerY) {
              final upW = ((lm.centerY - ny) / (lm.height * 0.5)).clamp(0.0, 1.0);
              grid.dy[idx] -= (forehead * 0.035 * upW * falloff);
            }

            // 턱 높이 (하단)
            if (ny > lm.mouthY) {
              final downW = ((ny - lm.mouthY) / (lm.height * 0.4)).clamp(0.0, 1.0);
              grid.dy[idx] += (chinH * 0.04 * downW * falloff);
            }

            // 턱선 (Jawline: 턱 양옆을 안쪽으로 당김)
            if (ny > lm.noseY && dxF.abs() > lm.width * 0.12) {
              final jawW = ((ny - lm.noseY) / (lm.height * 0.4)).clamp(0.0, 1.0);
              final dirX = dxF > 0 ? -1.0 : 1.0;
              grid.dx[idx] += dirX * (jawline * 0.05 * jawW * falloff);
            }

            // 얼굴 전체 너비 (뺨/볼 축소)
            if (dxF.abs() > lm.width * 0.08) {
              final dirX = dxF > 0 ? -1.0 : 1.0;
              grid.dx[idx] += dirX * (faceW * 0.045 * falloff);
            }
          }
        }
      }
    }
  }

  /// 32-bit FloatImage에 유동화 변위 워핑 적용 (역방향 매핑 + Bilinear Interpolation)
  static void applyWarpToFloatBuffer({
    required Float32List buf,
    required int w,
    required int h,
    required LiquifyDisplacementGrid grid,
  }) {
    if (grid.isEmpty) return;

    final orig = Float32List.fromList(buf);
    final invW = 1.0 / w;
    final invH = 1.0 / h;

    for (var y = 0; y < h; y++) {
      final ny = y * invH;
      final rowOffset = y * w;

      for (var x = 0; x < w; x++) {
        final nx = x * invW;

        // 변위 샘플링 (dx, dy)
        final (offX, offY) = grid.sample(nx, ny);
        if (offX.abs() < 1e-6 && offY.abs() < 1e-6) continue;

        // 원본 좌표 역추적 (Inverse Mapping)
        final srcX = (x - offX * w).clamp(0.0, (w - 1).toDouble());
        final srcY = (y - offY * h).clamp(0.0, (h - 1).toDouble());

        final x0 = srcX.floor();
        final y0 = srcY.floor();
        final x1 = math.min(w - 1, x0 + 1);
        final y1 = math.min(h - 1, y0 + 1);

        final fx = srcX - x0;
        final fy = srcY - y0;

        final i00 = (y0 * w + x0) * 3;
        final i10 = (y0 * w + x1) * 3;
        final i01 = (y1 * w + x0) * 3;
        final i11 = (y1 * w + x1) * 3;

        final di = (rowOffset + x) * 3;
        for (var ch = 0; ch < 3; ch++) {
          final top = orig[i00 + ch] * (1.0 - fx) + orig[i10 + ch] * fx;
          final bot = orig[i01 + ch] * (1.0 - fx) + orig[i11 + ch] * fx;
          buf[di + ch] = (top * (1.0 - fy) + bot * fy);
        }
      }
    }
  }
}
