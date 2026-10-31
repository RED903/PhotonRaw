import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

/// 로드된 이미지 메타데이터 및 비트맵 데이터
class LoadedImage {
  final String name;
  final String path;
  final int width;
  final int height;
  final img.Image rawImage;
  final img.Image previewImage; // 빠른 실시간 인터랙션을 위한 프리뷰 캐시

  LoadedImage({
    required this.name,
    required this.path,
    required this.width,
    required this.height,
    required this.rawImage,
    required this.previewImage,
  });
}

/// 이미지 및 RAW 파일 입출력 서비스
class ImageService {
  /// 크로스 플랫폼 파일 열기 대화상자
  static Future<LoadedImage?> pickAndLoadImage() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'dng', 'cr2', 'nef', 'arw', 'raf', 'rw2', 'orf', // RAW 포맷
        'tiff', 'tif', 'png', 'jpg', 'jpeg', 'webp' // 표준 이미지
      ],
    );

    if (files.isEmpty) return null;
    final file = files.first;

    final bytes = await file.readAsBytes();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('지원되지 않거나 손상된 이미지 파일입니다: ${file.name}');
    }

    // 작업 반응성을 위해 최대 가로/세로 1600px 프리뷰 리사이즈 생성
    img.Image preview = decoded;
    if (decoded.width > 1600 || decoded.height > 1600) {
      preview = img.copyResize(
        decoded,
        width: decoded.width > decoded.height ? 1600 : null,
        height: decoded.height >= decoded.width ? 1600 : null,
        interpolation: img.Interpolation.linear,
      );
    }

    return LoadedImage(
      name: file.name,
      path: file.path ?? file.name,
      width: decoded.width,
      height: decoded.height,
      rawImage: decoded,
      previewImage: preview,
    );
  }

  /// 샘플 이미지 생성 (초기 테스트 및 즉시 체험용)
  static LoadedImage createSampleScene() {
    const width = 1280;
    const height = 720;
    final image = img.Image(width: width, height: height);

    // 하늘 그라데이션, 산 실루엣, 태양 하이라이트를 가진 풍경 씬 렌더링
    for (int y = 0; y < height; y++) {
      final ny = y / height;
      for (int x = 0; x < width; x++) {
        final nx = x / width;

        // 하늘 그라데이션 (새벽/노을 빛)
        double r = (1.0 - ny) * 0.4 + 0.3;
        double g = (1.0 - ny) * 0.5 + 0.4;
        double b = (1.0 - ny) * 0.9 + 0.1;

        // 태양 하이라이트 광원 (강렬한 노출 테스트용)
        final sunDx = nx - 0.7;
        final sunDy = ny - 0.3;
        final sunDist = math.sqrt(sunDx * sunDx + sunDy * sunDy);
        if (sunDist < 0.25) {
          final intensity = math.pow((0.25 - sunDist) / 0.25, 2.0) * 1.5;
          r += intensity * 1.2;
          g += intensity * 0.95;
          b += intensity * 0.7;
        }

        // 산 실루엣 지형 (섀도우 복원 테스트용)
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

    return LoadedImage(
      name: 'Sample_Landscape_32bit.raw',
      path: 'sample://landscape',
      width: width,
      height: height,
      rawImage: image,
      previewImage: image,
    );
  }

  /// 파일 저장 (내보내기)
  static Future<String?> exportImage({
    required img.Image image,
    required String defaultName,
    String format = 'jpg',
  }) async {
    Uint8List encoded;
    String mimeType = 'image/jpeg';

    if (format.toLowerCase() == 'png') {
      encoded = Uint8List.fromList(img.encodePng(image));
      mimeType = 'image/png';
    } else if (format.toLowerCase() == 'tiff') {
      encoded = Uint8List.fromList(img.encodeTiff(image));
      mimeType = 'image/tiff';
    } else {
      encoded = Uint8List.fromList(img.encodeJpg(image, quality: 95));
      mimeType = 'image/jpeg';
    }

    final saveUri = await FilePicker.saveFile(
      dialogTitle: '보정된 이미지 내보내기',
      fileName: 'PhotonRaw_$defaultName.$format',
      bytes: encoded,
      mimeType: mimeType,
    );

    return saveUri?.toString();
  }
}
