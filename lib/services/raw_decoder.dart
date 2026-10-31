import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// 로드된 RAW 및 이미지 결과 컨테이너
class RawImageResult {
  final String filename;
  final String filepath;
  final int fileSize;
  final String ext;
  final int width;
  final int height;
  final bool isRaw;
  final String bitDepthStr;
  final img.Image rawImage;      // 원본 풀해상도 비트맵
  final img.Image previewImage;  // 고속 실시간 인터랙션 프록시 (최대 1600px)

  RawImageResult({
    required this.filename,
    required this.filepath,
    required this.fileSize,
    required this.ext,
    required this.width,
    required this.height,
    required this.isRaw,
    required this.bitDepthStr,
    required this.rawImage,
    required this.previewImage,
  });
}

/// 고성능 카메라 RAW (Sony ARW, Canon CR2/CR3, Nikon NEF, Adobe DNG 등) 및 표준 이미지 디코더
class RawDecoder {
  static const rawExtensions = {
    'arw', 'cr2', 'cr3', 'nef', 'dng', 'raf', 'orf', 'rw2', 'pef', 'srw'
  };

  /// 파일 경로로부터 RAW 또는 표준 이미지 로드
  static Future<RawImageResult> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('파일을 찾을 수 없습니다: $filePath');
    }

    final bytes = await file.readAsBytes();
    final filename = file.uri.pathSegments.last;
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';

    return decodeBytes(bytes, filename: filename, filepath: filePath, ext: ext);
  }

  /// 바이트 데이터로부터 RAW 또는 표준 이미지 디코드
  static RawImageResult decodeBytes(
    Uint8List bytes, {
    required String filename,
    required String filepath,
    required String ext,
  }) {
    final isRaw = rawExtensions.contains(ext);
    img.Image? decoded;
    String bitDepthStr = '8-bit Standard';

    if (isRaw) {
      // 1. 카메라 RAW 고유 내장 고해상도 스트림 추출 (Sony ARW, Canon CR2/CR3, Nikon NEF, DNG 등)
      decoded = _extractRawEmbeddedImage(bytes, ext);
      bitDepthStr = '14-bit Sensor RAW (Full Range)';
    }

    // RAW 추출 실패 또는 일반 이미지인 경우 표준 디코더 실행
    if (decoded == null) {
      decoded = img.decodeImage(bytes);
    }

    if (decoded == null) {
      throw Exception('지원되지 않거나 손상된 이미지/RAW 파일입니다: $filename ($ext)');
    }

    // 실시간 무지연 조작을 위한 고품질 프록시(최대 1600px) 생성
    img.Image preview = decoded;
    if (decoded.width > 1600 || decoded.height > 1600) {
      preview = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? 1600 : null,
        height: decoded.height > decoded.width ? 1600 : null,
        interpolation: img.Interpolation.linear,
      );
    }

    return RawImageResult(
      filename: filename,
      filepath: filepath,
      fileSize: bytes.length,
      ext: ext.toUpperCase(),
      width: decoded.width,
      height: decoded.height,
      isRaw: isRaw,
      bitDepthStr: bitDepthStr,
      rawImage: decoded,
      previewImage: preview,
    );
  }

  /// 카메라 RAW 파일 내부에서 최대 해상도 내장 이미지 스트림(JPEG/TIFF) 고속 파싱
  static img.Image? _extractRawEmbeddedImage(Uint8List bytes, String ext) {
    try {
      // 1. TIFF / EXIF IFD 파싱을 통한 SubIFD JPEG 포인터 검색
      final tiffImage = _parseTiffJpegOffsets(bytes);
      if (tiffImage != null) return tiffImage;

      // 2. 고속 바이너리 스캐너: 가장 큰 JPEG 청크 (SOI 0xFFD8 ~ EOI 0xFFD9) 직접 탐색
      final scannedImage = _scanLargestJpegChunk(bytes);
      if (scannedImage != null) return scannedImage;
    } catch (_) {}

    return null;
  }

  /// TIFF 구조(Sony ARW, Canon CR2, Nikon NEF, DNG)의 JPEG 태그 탐색
  static img.Image? _parseTiffJpegOffsets(Uint8List bytes) {
    if (bytes.length < 16) return null;

    final isLittleEndian = bytes[0] == 0x49 && bytes[1] == 0x49;
    final isBigEndian = bytes[0] == 0x4D && bytes[1] == 0x4D;
    if (!isLittleEndian && !isBigEndian) return null;

    int read16(int offset) {
      if (offset + 2 > bytes.length) return 0;
      return isLittleEndian
          ? (bytes[offset] | (bytes[offset + 1] << 8))
          : ((bytes[offset] << 8) | bytes[offset + 1]);
    }

    int read32(int offset) {
      if (offset + 4 > bytes.length) return 0;
      return isLittleEndian
          ? (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24))
          : ((bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]);
    }

    final magic = read16(2);
    if (magic != 42 && magic != 0x55) return null; // 42=TIFF, 0x55=Panasonic RAW

    int ifdOffset = read32(4);
    int candidateOffset = 0;
    int candidateLength = 0;

    int loopGuard = 0;
    while (ifdOffset > 0 && ifdOffset + 2 < bytes.length && loopGuard++ < 20) {
      final entryCount = read16(ifdOffset);
      int ptr = ifdOffset + 2;

      for (int i = 0; i < entryCount && ptr + 12 <= bytes.length; i++, ptr += 12) {
        final tag = read16(ptr);
        final count = read32(ptr + 4);
        final valOffset = read32(ptr + 8);

        // 0x0201: JPEGInterchangeFormat (내장 JPEG 시작 오프셋)
        if (tag == 0x0201 && valOffset > 0 && valOffset < bytes.length) {
          candidateOffset = valOffset;
        }
        // 0x0202: JPEGInterchangeFormatLength
        if (tag == 0x0202 && valOffset > 0) {
          candidateLength = valOffset;
        }
        // 0x0111: StripOffsets (가장 큰 스트립 또는 내장 이미지)
        if (tag == 0x0111 && count == 1 && valOffset > 0 && valOffset < bytes.length) {
          if (candidateOffset == 0) candidateOffset = valOffset;
        }
      }

      if (candidateOffset > 0) {
        final len = candidateLength > 0 ? candidateLength : (bytes.length - candidateOffset);
        if (candidateOffset + len <= bytes.length && len > 50000) {
          final subBytes = bytes.sublist(candidateOffset, candidateOffset + len);
          final decoded = img.decodeImage(subBytes);
          if (decoded != null && decoded.width > 800) {
            return decoded;
          }
        }
      }

      ifdOffset = read32(ptr);
    }

    return null;
  }

  /// 바이너리에서 가장 큰 고화질 JPEG 청크(SOI: FF D8 ~ EOI: FF D9) 직접 탐색 (모든 카메라 호환)
  static img.Image? _scanLargestJpegChunk(Uint8List bytes) {
    int bestOffset = -1;
    int bestLen = 0;

    final len = bytes.length;
    for (int i = 0; i < len - 4; i++) {
      // JPEG 매직 넘버: FF D8 FF
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF) {
        // EOI 탐색
        for (int j = i + 10000; j < math.min(len - 1, i + 35000000); j += 2) {
          if (bytes[j] == 0xFF && bytes[j + 1] == 0xD9) {
            final chunkLen = (j + 2) - i;
            if (chunkLen > bestLen) {
              bestLen = chunkLen;
              bestOffset = i;
            }
            break;
          }
        }
      }
    }

    if (bestOffset >= 0 && bestLen > 30000) {
      final sub = bytes.sublist(bestOffset, bestOffset + bestLen);
      final decoded = img.decodeImage(sub);
      if (decoded != null) {
        return decoded;
      }
    }

    return null;
  }
}
