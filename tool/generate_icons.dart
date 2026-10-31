import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// PhotonRaw 미니멀 & 모던 플랫(단색 배열) 'P' 로고 아이콘 생성기
/// - 그라데이션, 빛 번짐(Glow), 그림자 없이 완벽하게 깔끔한 단색(Solid Flat Color) 배열로 구성
/// - 4x4 슈퍼샘플링 안티앨리어싱(SSAA)으로 경계선만 칼같이 매끄럽게 처리
/// - 구성:
///   1) 배경: 깔끔한 매트 차콜 다크 (#18191C) 스쿼클(Squircle)
///   2) 좌측 수직 기둥(Stem): 깔끔한 퓨어 화이트 (#F4F5F7) — 하단 사선 모던 컷
///   3) 우측 P 루프(Bowl Arc): 기둥과 모던한 간격(Gap)을 두고 분리된 솔리드 포톤 앰버 (#E8A838)
///   4) 루프 중앙 포인트: 카메라 렌즈/광자를 상징하는 깔끔한 작은 원형 도트 (#E8A838)
img.Image renderPhotonRawIcon(int targetSize, {bool circularMask = true}) {
  final int baseSize = math.max(512, targetSize);
  final canvas = img.Image(width: baseSize, height: baseSize, numChannels: 4);

  // 단색 팔레트 (그라데이션 전혀 없음)
  const bgR = 24.0, bgG = 25.0, bgB = 28.0; // #18191C 깔끔한 다크 배경
  const borderR = 44.0, borderG = 46.0, borderB = 52.0; // #2C2E34 얇고 깔끔한 외곽선
  const stemR = 244.0, stemG = 245.0, stemB = 247.0; // #F4F5F7 모던 화이트 기둥
  const loopR = 232.0, loopG = 168.0, loopB = 56.0; // #E8A838 시그니처 앰버 루프

  // 4x4 서브픽셀 슈퍼샘플링 오프셋 (경계선 계단현상 제거용)
  const subSamples = 4;
  const invSub = 1.0 / subSamples;
  const totalSamples = subSamples * subSamples;

  for (int y = 0; y < baseSize; y++) {
    for (int x = 0; x < baseSize; x++) {
      double sumR = 0.0;
      double sumG = 0.0;
      double sumB = 0.0;
      double sumA = 0.0;

      for (int sy = 0; sy < subSamples; sy++) {
        final ny = (y + (sy + 0.5) * invSub) / baseSize;
        final cy = (ny - 0.5) * 2.0;

        for (int sx = 0; sx < subSamples; sx++) {
          final nx = (x + (sx + 0.5) * invSub) / baseSize;
          final cx = (nx - 0.5) * 2.0;

          // 1. 스쿼클(Superellipse) 마스크 판별
          if (circularMask) {
            final ax = cx.abs() / 0.90;
            final ay = cy.abs() / 0.90;
            final squircle =
                math.pow(math.pow(ax, 5.0) + math.pow(ay, 5.0), 1.0 / 5.0);
            if (squircle > 1.0) {
              continue; // 투명 영역
            }
            // 외곽 얇은 단색 보더 라인
            if (squircle > 0.965) {
              sumR += borderR;
              sumG += borderG;
              sumB += borderB;
              sumA += 1.0;
              continue;
            }
          }

          // 기본 단색 배경
          double pr = bgR;
          double pg = bgG;
          double pb = bgB;

          // 2. 모던 기하학적 'P' 심볼 판별 (단색 도형 배열)
          final shapeId = _hitTestModernP(nx, ny);
          if (shapeId == 1) {
            // 좌측 기둥 (단색 화이트)
            pr = stemR;
            pg = stemG;
            pb = stemB;
          } else if (shapeId == 2) {
            // 우측 P 보울 & 중앙 포톤 도트 (단색 앰버 골드)
            pr = loopR;
            pg = loopG;
            pb = loopB;
          }

          sumR += pr;
          sumG += pg;
          sumB += pb;
          sumA += 1.0;
        }
      }

      if (sumA <= 0.0) {
        canvas.setPixelRgba(x, y, 0, 0, 0, 0);
      } else {
        // 프리멀티플라이드 알파 보정 없이 내부 픽셀 색상 평균과 커버리지 알파 결합
        final r = (sumR / sumA).round().clamp(0, 255);
        final g = (sumG / sumA).round().clamp(0, 255);
        final b = (sumB / sumA).round().clamp(0, 255);
        final a = ((sumA / totalSamples) * 255.0).round().clamp(0, 255);
        canvas.setPixelRgba(x, y, r, g, b, a);
      }
    }
  }

  if (targetSize == baseSize) {
    return canvas;
  }
  return img.copyResize(
    canvas,
    width: targetSize,
    height: targetSize,
    interpolation: img.Interpolation.cubic,
  );
}

/// 모던 'P' 도형 히트 테스트
/// 반환값:
///   0 = 배경
///   1 = 좌측 수직 기둥 (단색 화이트)
///   2 = 우측 P 아크 보울 (단색 앰버)
int _hitTestModernP(double nx, double ny) {
  // --- 도형 1: 좌측 수직 기둥 (Stem) ---
  // x: [0.255, 0.375] (폭 0.12), y: [0.21, 0.79]
  // 상단과 하단 모두 사선 없이 반듯한 일자(수평) + 깔끔한 라운드 모서리
  const stemLeft = 0.255;
  const stemRight = 0.375;
  const stemTop = 0.21;
  const stemBottom = 0.79;
  const stemCornerR = 0.024;

  final dStemX = math.max(stemLeft - nx, nx - stemRight);
  final dStemY = math.max(stemTop - ny, ny - stemBottom);
  final stemSdf = _roundedBoxSdf(dStemX, dStemY, stemCornerR);
  if (stemSdf <= 0.0) {
    return 1;
  }

  // --- 도형 2: 우측 'P' 루프 아크 (Bowl) ---
  // 기둥 오른쪽(x = 0.375)에서 0.030 만큼의 깔끔한 네거티브 스페이스(Gap)를 두고 x = 0.405부터 시작하는 모던 스플릿 P 디자인
  const gapLeft = 0.405;
  const bowlCenterX = 0.515;
  const bowlCenterY = 0.415;
  const outerR = 0.205; // 상단 0.21, 하단 0.62, 우측 끝 0.72
  const innerR = 0.085; // 두께 0.12 (기둥 폭과 정확히 1:1 비례)
  const capRadius = 0.022;

  if (nx >= gapLeft) {
    // 상단 수평 바 + 우측 반원 + 하단 수평 바가 하나의 매끄러운 U자 아크로 이어지도록 통합 계산
    // x < bowlCenterX 구간에서는 중심점을 (gapLeft + capRadius, y) ~ (bowlCenterX, y) 선분으로 투영하고,
    // x >= bowlCenterX 구간에서는 중심점 (bowlCenterX, bowlCenterY)로부터의 반지름으로 계산
    final midR = (outerR + innerR) * 0.5; // 0.145
    final halfThick = (outerR - innerR) * 0.5; // 0.060

    if (nx >= bowlCenterX) {
      final dx = nx - bowlCenterX;
      final dy = ny - bowlCenterY;
      final r = math.sqrt(dx * dx + dy * dy);
      if ((r - midR).abs() <= halfThick) {
        return 2;
      }
    } else {
      // 좌측 끝(gapLeft)은 작은 라운드(capRadius)만 주고 bowlCenterX까지는 직선 수평 바로 매끄럽게 연결
      final topCenterY = bowlCenterY - midR;
      final botCenterY = bowlCenterY + midR;
      final targetCy = (ny < bowlCenterY) ? topCenterY : botCenterY;
      final dy = (ny - targetCy).abs() - halfThick;
      final dx = gapLeft - nx; // nx >= gapLeft 이므로 dx <= 0
      if (_roundedBoxSdf(dx, dy, capRadius) <= 0.0) {
        return 2;
      }
    }
  }

  return 0;
}

double _roundedBoxSdf(double dx, double dy, double r) {
  final qx = dx + r;
  final qy = dy + r;
  final outDist = math.sqrt(
    math.max(qx, 0.0) * math.max(qx, 0.0) +
        math.max(qy, 0.0) * math.max(qy, 0.0),
  );
  final inDist = math.min(math.max(qx, qy), 0.0);
  return outDist + inDist - r;
}

/// 다중 해상도 PNG 페이로드 기반 Windows .ico 바이너리 생성
Uint8List buildWindowsIco(List<int> sizes, img.Image master1024) {
  final pngPayloads = <Uint8List>[];
  for (final s in sizes) {
    final resized = img.copyResize(
      master1024,
      width: s,
      height: s,
      interpolation: img.Interpolation.cubic,
    );
    pngPayloads.add(Uint8List.fromList(img.encodePng(resized)));
  }

  final count = sizes.length;
  final headerSize = 6 + count * 16;
  int totalSize = headerSize;
  for (final p in pngPayloads) {
    totalSize += p.length;
  }

  final out = ByteData(totalSize);
  out.setUint16(0, 0, Endian.little);
  out.setUint16(2, 1, Endian.little);
  out.setUint16(4, count, Endian.little);

  int offset = headerSize;
  for (int i = 0; i < count; i++) {
    final s = sizes[i];
    final payload = pngPayloads[i];
    final entryPos = 6 + i * 16;
    out.setUint8(entryPos + 0, s >= 256 ? 0 : s);
    out.setUint8(entryPos + 1, s >= 256 ? 0 : s);
    out.setUint8(entryPos + 2, 0);
    out.setUint8(entryPos + 3, 0);
    out.setUint16(entryPos + 4, 1, Endian.little);
    out.setUint16(entryPos + 6, 32, Endian.little);
    out.setUint32(entryPos + 8, payload.length, Endian.little);
    out.setUint32(entryPos + 12, offset, Endian.little);

    final bytesView = out.buffer.asUint8List();
    bytesView.setRange(offset, offset + payload.length, payload);
    offset += payload.length;
  }

  return out.buffer.asUint8List();
}

void main() {
  print('Generating clean flat solid-color modern P icons for PhotonRaw...');
  final masterRound1024 = renderPhotonRawIcon(1024, circularMask: true);
  final masterFull1024 = renderPhotonRawIcon(1024, circularMask: false);

  void savePng(String path, int size, {bool fullBleed = false}) {
    final src = fullBleed ? masterFull1024 : masterRound1024;
    final resized = size == 1024
        ? src
        : img.copyResize(
            src,
            width: size,
            height: size,
            interpolation: img.Interpolation.cubic,
          );
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(resized));
  }

  // 1. Android mipmap icons
  final androidMipmaps = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  for (final entry in androidMipmaps.entries) {
    savePng(
      'android/app/src/main/res/${entry.key}/ic_launcher.png',
      entry.value,
      fullBleed: false,
    );
  }

  // 2. Windows app_icon.ico
  final icoBytes = buildWindowsIco([16, 32, 48, 64, 128, 256], masterRound1024);
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(icoBytes);

  // 3. macOS AppIcon.appiconset
  final macSizes = [16, 32, 64, 128, 256, 512, 1024];
  for (final s in macSizes) {
    savePng(
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$s.png',
      s,
      fullBleed: false,
    );
  }

  // 4. iOS AppIcon.appiconset
  final iosIcons = {
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  for (final entry in iosIcons.entries) {
    savePng(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/${entry.key}',
      entry.value,
      fullBleed: true,
    );
  }

  // 5. Web icons
  savePng('web/favicon.png', 64, fullBleed: false);
  savePng('web/icons/Icon-192.png', 192, fullBleed: false);
  savePng('web/icons/Icon-512.png', 512, fullBleed: false);
  savePng('web/icons/Icon-maskable-192.png', 192, fullBleed: true);
  savePng('web/icons/Icon-maskable-512.png', 512, fullBleed: true);

  // 6. 미리보기 PNG 저장
  savePng(
    r'C:\Users\red00\.gemini\antigravity\brain\9ead3063-ca24-42e8-98ca-210a84bcb229\photon_raw_icon_preview.png',
    512,
    fullBleed: false,
  );
  print('All flat solid-color icons generated successfully!');
}
