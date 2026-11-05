import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;

import 'pipeline_core.dart';
import 'xmp_service.dart';

/// 디코딩 완료된 풀 해상도 이미지 (14/16-bit RAW의 경우 [linearRgb]에 무손실 32-bit 선형 Float 보유)
class DecodedImage {
  final String name;
  final String path;
  final String ext;
  final int fileSize;
  final int width;
  final int height;
  final bool isRaw;
  final int bitDepth;
  final String camera;
  final String lensModel;
  final double focalLength;
  final double aperture;
  final String note;
  final double asShotTemp;
  final double asShotTint;
  final int rating; // XMP 사이드카 또는 메타데이터 별점 (0 ~ 5)
  final String xmpPath;
  final Uint8List rgb; // 빠른 히스토그램/자동노출 참조 및 8-bit 이미지용
  final Float32List? linearRgb; // 14/16-bit RAW 및 16-bit 이미지용 무손실 32-bit Float 선형 RGB

  DecodedImage({
    required this.name,
    required this.path,
    required this.ext,
    required this.fileSize,
    required this.width,
    required this.height,
    required this.isRaw,
    required this.bitDepth,
    required this.camera,
    this.lensModel = '',
    this.focalLength = 0.0,
    this.aperture = 0.0,
    required this.note,
    this.asShotTemp = 6500.0,
    this.asShotTint = 0.0,
    this.rating = 0,
    this.xmpPath = '',
    required this.rgb,
    this.linearRgb,
  });
}

const Set<String> kRawExtensions = {
  'arw',
  'cr2',
  'cr3',
  'nef',
  'dng',
  'raf',
  'orf',
  'rw2',
  'pef',
  'srw',
  'kdc',
  'mos',
};
const Set<String> kImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'tif',
  'tiff',
  'bmp',
  'webp',
};

bool isSupportedPath(String path) {
  final e = _extOf(path);
  return kRawExtensions.contains(e) || kImageExtensions.contains(e);
}

String _extOf(String path) {
  final i = path.lastIndexOf('.');
  if (i < 0 || i == path.length - 1) return '';
  return path.substring(i + 1).toLowerCase();
}

String _nameOf(String path) {
  final s = path.replaceAll('\\', '/');
  final i = s.lastIndexOf('/');
  return i < 0 ? s : s.substring(i + 1);
}

/// 파일을 읽어 디코딩 (백그라운드 Isolate 안에서 호출)
/// - RAW 파일은 반드시 12/14/16-bit 센서 데이터로 직접 디코딩하며, 8-bit 내장 JPEG 프리뷰로 폴백하는 것을 원천 금지함!
DecodedImage decodeImageFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw Exception('파일을 찾을 수 없습니다: $path');
  }
  final ext = _extOf(path);
  final name = _nameOf(path);

  DecodedImage decodedImg;
  if (kRawExtensions.contains(ext)) {
    decodedImg = _decodeTrueRaw16Bit(file, name, path, ext);
  } else {
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('지원되지 않거나 손상된 이미지입니다: $name');
    }
    img.Image image = decoded;
    var camera = '';
    var lensModel = '';
    double focalLength = 0.0;
    double aperture = 0.0;
    try {
      final make = image.exif.imageIfd.make ?? '';
      final model = image.exif.imageIfd.model ?? '';
      camera = '$make $model'.trim();
      final exif = image.exif;
      lensModel = exif.getTag(0xA434)?.toString() ?? '';
      final tagFocal = exif.getTag(0x920A);
      if (tagFocal != null) focalLength = double.tryParse(tagFocal.toString()) ?? 0.0;
      final tagFNum = exif.getTag(0x829D);
      if (tagFNum != null) aperture = double.tryParse(tagFNum.toString()) ?? 0.0;
    } catch (_) {}
    try {
      image = img.bakeOrientation(image);
    } catch (_) {}

    final is16BitImg = image.format == img.Format.uint16;
    Float32List? linearF32;
    if (is16BitImg) {
      final c16 = image.numChannels == 3
          ? image
          : image.convert(format: img.Format.uint16, numChannels: 3);
      final u16 = Uint16List.view(
        c16.getBytes(order: img.ChannelOrder.rgb).buffer,
      );
      linearF32 = Float32List(u16.length);
      for (int i = 0; i < u16.length; i++) {
        final s = u16[i] / 65535.0;
        linearF32[i] = s <= 0.04045
            ? s / 12.92
            : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
      }
    }

    decodedImg = DecodedImage(
      name: name,
      path: path,
      ext: ext.toUpperCase(),
      fileSize: bytes.length,
      width: image.width,
      height: image.height,
      isRaw: false,
      bitDepth: is16BitImg ? 16 : 8,
      camera: camera.isEmpty ? '일반 이미지' : camera,
      lensModel: lensModel,
      focalLength: focalLength,
      aperture: aperture,
      note: is16BitImg ? '16-bit 무손실 이미지' : '8-bit 표준 이미지',
      rgb: _toRgbBytes(image),
      linearRgb: linearF32,
    );
  }

  // ── 다크테이블/라이트룸 XMP 사이드카 메타데이터 자동 결합 ──
  final xmp = XmpService.loadXmpSync(path);
  final finalLens = (xmp.lensModel.isNotEmpty) ? xmp.lensModel : decodedImg.lensModel;
  final finalCamera = (xmp.cameraModel.isNotEmpty && decodedImg.camera.isEmpty)
      ? '${xmp.cameraMake} ${xmp.cameraModel}'.trim()
      : decodedImg.camera;
  final finalFocal = (xmp.focalLength != null && decodedImg.focalLength == 0.0)
      ? xmp.focalLength!
      : decodedImg.focalLength;
  final finalAperture = (xmp.fNumber != null && decodedImg.aperture == 0.0)
      ? xmp.fNumber!
      : decodedImg.aperture;

  return DecodedImage(
    name: decodedImg.name,
    path: decodedImg.path,
    ext: decodedImg.ext,
    fileSize: decodedImg.fileSize,
    width: decodedImg.width,
    height: decodedImg.height,
    isRaw: decodedImg.isRaw,
    bitDepth: decodedImg.bitDepth,
    camera: finalCamera,
    lensModel: finalLens,
    focalLength: finalFocal,
    aperture: finalAperture,
    note: decodedImg.note,
    asShotTemp: decodedImg.asShotTemp,
    asShotTint: decodedImg.asShotTint,
    rating: xmp.rating,
    xmpPath: xmp.xmpPath,
    rgb: decodedImg.rgb,
    linearRgb: decodedImg.linearRgb,
  );
}

Uint8List _toRgbBytes(img.Image im) {
  final c = (im.numChannels == 3 && im.format == img.Format.uint8)
      ? im
      : im.convert(format: img.Format.uint8, numChannels: 3);
  return c.getBytes(order: img.ChannelOrder.rgb);
}

// ───────────────────── 14/16-bit 순수 센서 RAW 디코딩 (8-bit JPEG 폴백 원천 차단) ─────────────────────

DecodedImage _decodeTrueRaw16Bit(
  File file,
  String name,
  String path,
  String ext,
) {
  final fileSize = file.lengthSync();

  // 1순위: 네이티브 LibRaw 16-bit FFI 디코더 시도 (Windows raw_r.dll / macOS / Linux)
  final libRawResult = _LibRawFfiDecoder.tryDecode16Bit(
    path: path,
    name: name,
    ext: ext,
    fileSize: fileSize,
  );
  if (libRawResult != null) {
    return libRawResult;
  }

  // 2순위: 순수 Dart 12/14/16-bit 베이어 센서 직접 디코더 (Sony ARW2 14-bit / 비압축 ARW / DNG / TIFF CFA — Android/iOS 포함 전 플랫폼 작동)
  final bytes = file.readAsBytesSync();
  final nativeBayerResult = _PureDartBayerRawDecoder.tryDecodeSensor(
    bytes: bytes,
    name: name,
    path: path,
    ext: ext,
  );
  if (nativeBayerResult != null) {
    return nativeBayerResult;
  }

  // 8-bit 내장 JPEG 폴백은 절대 수행하지 않고, 즉시 불러올 수 없다는 오류를 발생시킴
  throw Exception(
    '$name: 14/16-bit 센서 RAW 데이터를 디코딩할 수 없습니다 (8-bit JPEG 대체 로드 차단됨).',
  );
}

// ───────────────────── 1. LibRaw 16-bit Native FFI 디코더 ─────────────────────

typedef _LrInitNative = ffi.Pointer<ffi.Void> Function(ffi.Uint32 flags);
typedef _LrInitDart = ffi.Pointer<ffi.Void> Function(int flags);

typedef _LrOpenWFileNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> lr,
  ffi.Pointer<ffi.WChar> path,
);
typedef _LrOpenWFileDart = int Function(
  ffi.Pointer<ffi.Void> lr,
  ffi.Pointer<ffi.WChar> path,
);

typedef _LrOpenFileNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> lr,
  ffi.Pointer<Utf8> path,
);
typedef _LrOpenFileDart = int Function(
  ffi.Pointer<ffi.Void> lr,
  ffi.Pointer<Utf8> path,
);

typedef _LrActionNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> lr);
typedef _LrActionDart = int Function(ffi.Pointer<ffi.Void> lr);

typedef _LrVoidNative = ffi.Void Function(ffi.Pointer<ffi.Void> lr);
typedef _LrVoidDart = void Function(ffi.Pointer<ffi.Void> lr);

typedef _LrSetIntNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> lr,
  ffi.Int32 value,
);
typedef _LrSetIntDart = void Function(ffi.Pointer<ffi.Void> lr, int value);

typedef _LrSetGammaNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> lr,
  ffi.Int32 index,
  ffi.Float value,
);
typedef _LrSetGammaDart = void Function(
  ffi.Pointer<ffi.Void> lr,
  int index,
  double value,
);

typedef _LrGetFloatNative = ffi.Float Function(
  ffi.Pointer<ffi.Void> lr,
  ffi.Int32 index,
);
typedef _LrGetFloatDart = double Function(ffi.Pointer<ffi.Void> lr, int index);

typedef _LrMakeMemImgNative = ffi.Pointer<_LibRawProcessedImage> Function(
  ffi.Pointer<ffi.Void> lr,
  ffi.Pointer<ffi.Int32> errc,
);
typedef _LrMakeMemImgDart = ffi.Pointer<_LibRawProcessedImage> Function(
  ffi.Pointer<ffi.Void> lr,
  ffi.Pointer<ffi.Int32> errc,
);

typedef _LrClearMemNative = ffi.Void Function(
  ffi.Pointer<_LibRawProcessedImage> p,
);
typedef _LrClearMemDart = void Function(ffi.Pointer<_LibRawProcessedImage> p);

final class _LibRawProcessedImage extends ffi.Struct {
  @ffi.Int32()
  external int type;

  @ffi.Uint16()
  external int height;

  @ffi.Uint16()
  external int width;

  @ffi.Uint16()
  external int colors;

  @ffi.Uint16()
  external int bits;

  @ffi.Uint32()
  external int dataSize;

  @ffi.Array(1)
  external ffi.Array<ffi.Uint8> data;
}

class _LibRawFfiDecoder {
  static ffi.DynamicLibrary? _cachedLib;
  static bool _triedLoad = false;

  static ffi.DynamicLibrary? _loadLibrary() {
    if (_triedLoad) return _cachedLib;
    _triedLoad = true;

    final candidates = <String>[];
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.addAll([
        '$exeDir\\raw_r.dll',
        '$exeDir\\libraw.dll',
        'windows\\runner\\resources\\raw_r.dll',
        'raw_r.dll',
        'libraw.dll',
        r'C:\Users\red00\AppData\Local\Programs\Python\Python312\Lib\site-packages\rawpy\raw_r.dll',
      ]);
    } else if (Platform.isMacOS) {
      candidates.addAll([
        'libraw_r.dylib',
        'libraw.dylib',
        '/opt/homebrew/lib/libraw_r.dylib',
        '/usr/local/lib/libraw_r.dylib',
      ]);
    } else if (Platform.isLinux) {
      candidates.addAll(['libraw_r.so', 'libraw_r.so.23', 'libraw.so']);
    }

    for (final path in candidates) {
      try {
        if (path.contains('\\') || path.contains('/')) {
          final f = File(path);
          if (!f.existsSync()) continue;
          if (Platform.isWindows) {
            final vcomp = File('${f.parent.path}\\vcomp140.dll');
            if (vcomp.existsSync()) {
              try {
                ffi.DynamicLibrary.open(vcomp.path);
              } catch (_) {}
            }
          }
        }
        _cachedLib = ffi.DynamicLibrary.open(path);
        return _cachedLib;
      } catch (_) {}
    }
    return null;
  }

  static DecodedImage? tryDecode16Bit({
    required String path,
    required String name,
    required String ext,
    required int fileSize,
  }) {
    final lib = _loadLibrary();
    if (lib == null) return null;

    ffi.Pointer<ffi.Void> lr = ffi.nullptr;
    ffi.Pointer<_LibRawProcessedImage> memImg = ffi.nullptr;
    final errPtr = calloc<ffi.Int32>();

    try {
      final lrInit = lib.lookupFunction<_LrInitNative, _LrInitDart>(
        'libraw_init',
      );
      final lrUnpack = lib.lookupFunction<_LrActionNative, _LrActionDart>(
        'libraw_unpack',
      );
      final lrProcess = lib.lookupFunction<_LrActionNative, _LrActionDart>(
        'libraw_dcraw_process',
      );
      final lrMakeMem =
          lib.lookupFunction<_LrMakeMemImgNative, _LrMakeMemImgDart>(
        'libraw_dcraw_make_mem_image',
      );
      final lrClearMem = lib.lookupFunction<_LrClearMemNative, _LrClearMemDart>(
        'libraw_dcraw_clear_mem',
      );
      final lrClose = lib.lookupFunction<_LrVoidNative, _LrVoidDart>(
        'libraw_close',
      );
      final lrSetBps = lib.lookupFunction<_LrSetIntNative, _LrSetIntDart>(
        'libraw_set_output_bps',
      );
      final lrSetNoAutoBright =
          lib.lookupFunction<_LrSetIntNative, _LrSetIntDart>(
        'libraw_set_no_auto_bright',
      );
      final lrSetOutputColor =
          lib.lookupFunction<_LrSetIntNative, _LrSetIntDart>(
        'libraw_set_output_color',
      );
      final lrSetGamma = lib.lookupFunction<_LrSetGammaNative, _LrSetGammaDart>(
        'libraw_set_gamma',
      );
      final lrGetMax = lib.lookupFunction<_LrActionNative, _LrActionDart>(
        'libraw_get_color_maximum',
      );
      final lrGetCamMul =
          lib.lookupFunction<_LrGetFloatNative, _LrGetFloatDart>(
        'libraw_get_cam_mul',
      );
      final lrGetPreMul =
          lib.lookupFunction<_LrGetFloatNative, _LrGetFloatDart>(
        'libraw_get_pre_mul',
      );

      lr = lrInit(0);
      if (lr == ffi.nullptr) return null;

      int openRc = -1;
      if (Platform.isWindows) {
        final lrOpenW =
            lib.lookupFunction<_LrOpenWFileNative, _LrOpenWFileDart>(
          'libraw_open_wfile',
        );
        final wPath = path.toNativeUtf16();
        try {
          openRc = lrOpenW(lr, wPath.cast<ffi.WChar>());
        } finally {
          calloc.free(wPath);
        }
      } else {
        final lrOpen = lib.lookupFunction<_LrOpenFileNative, _LrOpenFileDart>(
          'libraw_open_file',
        );
        final uPath = path.toNativeUtf8();
        try {
          openRc = lrOpen(lr, uPath);
        } finally {
          calloc.free(uPath);
        }
      }
      if (openRc != 0) return null;

      if (lrUnpack(lr) != 0) return null;

      // SemiDarktable(raw_loader.py)과 100% 동일한 16-bit 선형 설정:
      // output_bps = 16, gamma = (1.0, 1.0), no_auto_bright = 1, output_color = 1 (sRGB), use_camera_wb = 1
      lrSetBps(lr, 16);
      lrSetNoAutoBright(lr, 1);
      lrSetGamma(lr, 0, 1.0);
      lrSetGamma(lr, 1, 1.0);

      // libraw_output_params_t 내부의 use_camera_wb = 1 설정
      // output_color 바로 앞에는 포인터가 전혀 없고 (use_camera_wb, use_camera_matrix, output_color) 연속된 int32로 배치됨
      try {
        const sentinel = 0x5A5A5A53;
        lrSetOutputColor(lr, sentinel);
        final baseInts = lr.cast<ffi.Int32>();
        for (int idx = 64; idx < 4096; idx++) {
          if (baseInts[idx] == sentinel &&
              baseInts[idx - 1] == 1 &&
              baseInts[idx - 2] == 0) {
            baseInts[idx - 2] = 1; // use_camera_wb = 1
            break;
          }
        }
      } catch (_) {}
      lrSetOutputColor(lr, 1);

      final whiteLevel = lrGetMax(lr);
      final bitDepth = whiteLevel <= 4095
          ? 12
          : (whiteLevel <= 16383 ? 14 : 16);

      // 촬영 당시 화이트밸런스(As-Shot WB) 색온도 역산 (카메라 및 Lightroom/LightCraft 표준 켈빈 기준, 틴트는 수동 조작 전용 0.0 고정)
      double asShotTemp = 5500.0;
      const double asShotTint = 0.0;
      try {
        final camR = lrGetCamMul(lr, 0);
        final camG = lrGetCamMul(lr, 1);
        final camB = lrGetCamMul(lr, 2);
        final dayR = lrGetPreMul(lr, 0);
        final dayG = lrGetPreMul(lr, 1);
        final dayB = lrGetPreMul(lr, 2);
        if (camG > 0.001 && dayG > 0.001 && camR > 0.001 && dayR > 0.001) {
          final rNorm = (camR / camG) / (dayR / dayG);
          final bNorm = (camB / camG) / math.max(0.001, dayB / dayG);
          if (rNorm > 0.001 && bNorm > 0.001) {
            final cct = 5500.0 * math.pow(rNorm / bNorm, 0.55);
            asShotTemp = ((cct / 50.0).round() * 50)
                .clamp(2000, 12000)
                .toDouble();
          }
        }
      } catch (_) {}

      if (lrProcess(lr) != 0) return null;

      memImg = lrMakeMem(lr, errPtr);
      if (memImg == ffi.nullptr) return null;

      final w = memImg.ref.width;
      final h = memImg.ref.height;
      final colors = memImg.ref.colors;
      final bits = memImg.ref.bits;

      // 8비트로 나온 경우 절대 허용하지 않음! 오직 16-bit 출력만 인정
      if (bits != 16 || colors < 3 || w <= 0 || h <= 0) {
        return null;
      }

      // data 필드의 오프셋 계산: type(4) + height(2) + width(2) + colors(2) + bits(2) + dataSize(4) = 16바이트
      final dataBytePtr = memImg.cast<ffi.Uint8>().elementAt(16);
      final u16Ptr = dataBytePtr.cast<ffi.Uint16>();
      final pixelCount = w * h;
      final u16View = u16Ptr.asTypedList(pixelCount * colors);

      // 최대값 확인 후 [0.0 ~ 1.0] 32-bit Float 선형 정규화 (SemiDarktable raw_loader.py 235~246행과 동일)
      int maxVal = 0;
      for (int i = 0; i < u16View.length; i += colors) {
        final r = u16View[i];
        final g = u16View[i + 1];
        final b = u16View[i + 2];
        if (r > maxVal) maxVal = r;
        if (g > maxVal) maxVal = g;
        if (b > maxVal) maxVal = b;
      }
      final double normDenom = (maxVal > 0 && maxVal <= whiteLevel * 1.05)
          ? whiteLevel.toDouble()
          : 65535.0;
      final invDenom = 1.0 / normDenom;

      // 65,536 단계 16-bit -> 32-bit Float / 8-bit sRGB 룩업 테이블 생성 (33MP 이상 고해상도 초고속 변환)
      final lutFloat32 = Float32List(65536);
      final lutSrgb8 = Uint8List(65536);
      for (int v = 0; v < 65536; v++) {
        final lf = (v * invDenom).clamp(0.0, 1.0);
        lutFloat32[v] = lf;
        lutSrgb8[v] = (linearToSrgb(lf) * 255.0 + 0.5).floor().clamp(0, 255);
      }

      final linearF32 = Float32List(pixelCount * 3);
      final previewRgb8 = Uint8List(pixelCount * 3);

      if (colors == 3) {
        final totalCh = pixelCount * 3;
        for (int i = 0; i < totalCh; i++) {
          final v = u16View[i];
          linearF32[i] = lutFloat32[v];
          previewRgb8[i] = lutSrgb8[v];
        }
      } else {
        for (int i = 0; i < pixelCount; i++) {
          final srcIdx = i * colors;
          final dstIdx = i * 3;
          final vR = u16View[srcIdx];
          final vG = u16View[srcIdx + 1];
          final vB = u16View[srcIdx + 2];

          linearF32[dstIdx] = lutFloat32[vR];
          linearF32[dstIdx + 1] = lutFloat32[vG];
          linearF32[dstIdx + 2] = lutFloat32[vB];

          previewRgb8[dstIdx] = lutSrgb8[vR];
          previewRgb8[dstIdx + 1] = lutSrgb8[vG];
          previewRgb8[dstIdx + 2] = lutSrgb8[vB];
        }
      }

      lrClearMem(memImg);
      memImg = ffi.nullptr;
      lrClose(lr);
      lr = ffi.nullptr;

      return DecodedImage(
        name: name,
        path: path,
        ext: ext.toUpperCase(),
        fileSize: fileSize,
        width: w,
        height: h,
        isRaw: true,
        bitDepth: bitDepth,
        camera: '${ext.toUpperCase()} $bitDepth-bit RAW',
        note: '✅ $bitDepth-bit 센서 RAW (32-bit Float 선형 파이프라인)',
        asShotTemp: asShotTemp,
        asShotTint: asShotTint,
        rgb: previewRgb8,
        linearRgb: linearF32,
      );
    } catch (_) {
      return null;
    } finally {
      calloc.free(errPtr);
      if (memImg != ffi.nullptr) {
        try {
          final lrClearMem = lib
              .lookupFunction<_LrClearMemNative, _LrClearMemDart>(
                'libraw_dcraw_clear_mem',
              );
          lrClearMem(memImg);
        } catch (_) {}
      }
      if (lr != ffi.nullptr) {
        try {
          final lrClose = lib.lookupFunction<_LrVoidNative, _LrVoidDart>(
            'libraw_close',
          );
          lrClose(lr);
        } catch (_) {}
      }
    }
  }
}

// ───────────── 2. 순수 Dart 14/16-bit 베이어 센서 디코더 (Android/iOS/Desktop 공통) ─────────────

/// 모바일(Android/iOS) 순수 Dart 14/16-bit 베이어 디코더 단독 검증용 진입점
DecodedImage? decodePureDartSensorForTest(String path) {
  final file = File(path);
  final bytes = file.readAsBytesSync();
  final name = path.split(RegExp(r'[/\\]')).last;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'arw';
  return _PureDartBayerRawDecoder.tryDecodeSensor(
    bytes: bytes,
    name: name,
    path: path,
    ext: ext,
  );
}

class _PureDartBayerRawDecoder {
  static DecodedImage? tryDecodeSensor({
    required Uint8List bytes,
    required String name,
    required String path,
    required String ext,
  }) {
    final tiff = _TiffSensorParser.tryCreate(bytes);
    if (tiff == null) return null;

    final rawIfd = tiff.findSensorRawIfd();
    if (rawIfd == null) return null;

    final width = tiff.readIntTag(rawIfd, 0x0100) ?? 0;
    final height = tiff.readIntTag(rawIfd, 0x0101) ?? 0;
    final compression = tiff.readIntTag(rawIfd, 0x0103) ?? 0;
    final bitsPerSample = tiff.readIntTag(rawIfd, 0x0102) ?? 14;
    if (width <= 64 || height <= 64) return null;

    final stripOffsets = tiff.readIntArrayTag(rawIfd, 0x0111);
    final stripByteCounts = tiff.readIntArrayTag(rawIfd, 0x0117);
    if (stripOffsets.isEmpty || stripByteCounts.isEmpty) return null;

    // 센서 블랙 레벨 & 화이트 레벨 추출
    final blackTag =
        tiff.readIntArrayTag(rawIfd, 0x7310).isNotEmpty
            ? tiff.readIntArrayTag(rawIfd, 0x7310)
            : tiff.readIntArrayTag(rawIfd, 0xC61A);
    final List<int> blackLevels = blackTag.length >= 4
        ? blackTag.sublist(0, 4)
        : (blackTag.isNotEmpty
              ? List<int>.filled(4, blackTag.first)
              : [512, 512, 512, 512]);

    int whiteLevel = tiff.readIntTag(rawIfd, 0xC61D) ?? 0;
    if (whiteLevel <= 0) {
      whiteLevel = compression == 32767
          ? 16380
          : ((1 << math.max(12, bitsPerSample)) - 1);
    }
    final actualBitDepth = whiteLevel <= 4095
        ? 12
        : (whiteLevel <= 16383 ? 14 : 16);

    // CFA 베이어 패턴 추출 (0=R, 1=G, 2=B)
    // 기본 RGGB = [0, 1, 1, 2]
    List<int> cfaPattern = tiff.readByteArrayTag(rawIfd, 0x828E);
    if (cfaPattern.length < 4) {
      cfaPattern = [0, 1, 1, 2];
    }

    // 촬영 화이트밸런스(As-Shot WB) 추출 (Sony 0x7313 WB_RGGBLevels = [R, G1, G2, B] 순서)
    List<int> sonyWb = tiff.readShortArrayTag(rawIfd, 0x7313);
    if (sonyWb.length < 4) {
      sonyWb = tiff.readShortArrayTag(tiff.ifd0, 0x7313);
    }
    double wbR = 2.55, wbG = 1.0, wbB = 1.48;
    double asShotTemp = 5500.0;
    const double asShotTint = 0.0;
    if (sonyWb.length >= 4) {
      // Sony 0x7313은 [R, G1, G2, B] 순서(예: [2811, 1024, 1024, 1440])로 저장되므로
      // G1(sonyWb[1])과 값이 가까운 쪽을 G2로, 나머지 하나를 B(블루 게인)로 정확히 매핑
      final rVal = sonyWb[0].toDouble();
      final g1Val = sonyWb[1].toDouble();
      final bool isRggbOrder =
          (sonyWb[1] - sonyWb[2]).abs() <= (sonyWb[1] - sonyWb[3]).abs();
      final g2Val = (isRggbOrder ? sonyWb[2] : sonyWb[3]).toDouble();
      final bVal = (isRggbOrder ? sonyWb[3] : sonyWb[2]).toDouble();
      final gAvg = (g1Val + g2Val) * 0.5;
      if (gAvg > 0 && rVal > 0 && bVal > 0) {
        wbR = rVal / gAvg;
        wbG = 1.0;
        wbB = bVal / gAvg;
        final rNorm = wbR / 2.52;
        final bNorm = wbB / 1.52;
        if (rNorm > 0.01 && bNorm > 0.01) {
          final cct = 5500.0 * math.pow(rNorm / bNorm, 0.55);
          asShotTemp =
              ((cct / 50.0).round() * 50).clamp(2000, 12000).toDouble();
        }
      }
    }

    // 베이어 16-bit 배열 디코딩
    Uint16List? bayer16;
    if (compression == 32767) {
      // Sony ARW2 14-bit 압축 센서 디코딩
      final sonyCurve = tiff.readShortArrayTag(rawIfd, 0x7010);
      bayer16 = _decodeSonyArw2Sensor(
        bytes: bytes,
        offset: stripOffsets.first,
        byteCount: stripByteCounts.first,
        width: width,
        height: height,
        sonyCurve: sonyCurve,
      );
    } else if (compression == 1) {
      // 비압축 12 / 14 / 16-bit 센서 디코딩
      bayer16 = _decodeUncompressedSensor(
        bytes: bytes,
        stripOffsets: stripOffsets,
        stripByteCounts: stripByteCounts,
        width: width,
        height: height,
        bitsPerSample: bitsPerSample,
        littleEndian: tiff.le,
      );
    }

    if (bayer16 == null) return null;

    // 4. 크롭 영역(ActiveArea / DefaultCropSize) 또는 센서 전체 영역에서 32-bit Float 디모자이킹 수행
    // 모바일에서도 메모리가 폭발하지 않고 빠르게 로드되도록 해상도가 2400px을 초과할 경우 2x2 초고속 슈퍼픽셀/Bilinear 디모자이킹 지원
    final demosaiced = _demosaicBayerToFloat32(
      bayer: bayer16,
      rawW: width,
      rawH: height,
      cfa: cfaPattern,
      blackLevels: blackLevels,
      whiteLevel: whiteLevel,
      wbR: wbR,
      wbG: wbG,
      wbB: wbB,
    );

    // 5. EXIF Orientation 반영 (1, 3, 6, 8)
    final orient = tiff.orientation();
    final oriented = _applyOrientationFloat(
      demosaiced.linearRgb,
      demosaiced.rgb8,
      demosaiced.width,
      demosaiced.height,
      orient,
    );

    final make = tiff.ascii(tiff.ifd0, 0x010F) ?? '';
    final model = tiff.ascii(tiff.ifd0, 0x0110) ?? '';
    final camera = '$make $model'.trim();
    final exifIfdOffset = tiff.readIntTag(tiff.ifd0, 0x8769);
    final lens = exifIfdOffset != null ? (tiff.ascii(exifIfdOffset, 0xA434) ?? '') : '';

    return DecodedImage(
      name: name,
      path: path,
      ext: ext.toUpperCase(),
      fileSize: bytes.length,
      width: oriented.width,
      height: oriented.height,
      isRaw: true,
      bitDepth: actualBitDepth,
      camera: camera.isEmpty ? '${ext.toUpperCase()} RAW' : camera,
      lensModel: lens,
      note: '✅ $actualBitDepth-bit 센서 RAW (32-bit Float 선형 파이프라인)',
      asShotTemp: asShotTemp,
      asShotTint: asShotTint,
      rgb: oriented.rgb8,
      linearRgb: oriented.linearRgb,
    );
  }

  /// Sony ARW2 (Compression 32767) 14-bit 센서 언패킹
  static Uint16List? _decodeSonyArw2Sensor({
    required Uint8List bytes,
    required int offset,
    required int byteCount,
    required int width,
    required int height,
    required List<int> sonyCurve,
  }) {
    if (offset <= 0 || offset + byteCount > bytes.length) return null;
    if (width % 32 != 0) return null;

    // Sony 12-bit -> 14-bit 비선형 커브 LUT 생성 (4096 엔트리)
    final c = <int>[0, 0, 0, 0, 0, 4095];
    for (int i = 0; i < 4 && i < sonyCurve.length; i++) {
      c[i + 1] = (sonyCurve[i] >> 2).clamp(0, 4095);
    }
    final curveLut = Uint16List(4096);
    for (int i = 0; i < 5; i++) {
      for (int j = c[i] + 1; j <= c[i + 1]; j++) {
        curveLut[j] = curveLut[j - 1] + (1 << i);
      }
    }

    final out = Uint16List(width * height);
    int srcPos = offset;

    for (int row = 0; row < height; row++) {
      final rowBase = row * width;
      // 한 행은 32픽셀(32바이트 = 16바이트 짝수열 블록 + 16바이트 홀수열 블록) 단위로 구성됨
      for (int col = 0; col < width; col += 32) {
        if (srcPos + 32 > bytes.length) break;

        // 블록 0 (짝수 열 16개 픽셀), 블록 1 (홀수 열 16개 픽셀)
        for (int blk = 0; blk < 2; blk++) {
          final bPos = srcPos + blk * 16;
          final w0 =
              bytes[bPos] |
              (bytes[bPos + 1] << 8) |
              (bytes[bPos + 2] << 16) |
              (bytes[bPos + 3] << 24);

          final maxVal = w0 & 0x7FF;
          final minVal = (w0 >> 11) & 0x7FF;
          final imax = (w0 >> 22) & 0x0F;
          final imin = (w0 >> 26) & 0x0F;

          int sh = 0;
          while (sh < 4 && ((maxVal - minVal) >> (sh + 7)) != 0) {
            sh++;
          }

          // 98비트 델타 스트림(14개 픽셀 * 7비트)을 두 개의 64비트 정수로 분리하여 읽기
          // bitOffset = 30 (바이트 3의 상위 2비트부터 시작)
          int bitPos = 30;
          for (int i = 0; i < 16; i++) {
            int val12;
            if (i == imax) {
              val12 = maxVal << 1;
            } else if (i == imin) {
              val12 = minVal << 1;
            } else {
              final byteIdx = bPos + (bitPos >> 3);
              final bitShift = bitPos & 7;
              final raw16 = bytes[byteIdx] | (bytes[byteIdx + 1] << 8);
              final delta7 = (raw16 >> bitShift) & 0x7F;
              bitPos += 7;
              val12 = (delta7 << (sh + 1)) + (minVal << 1) + (1 << sh);
            }
            final curved14 = curveLut[val12.clamp(0, 4095)];
            out[rowBase + col + (i << 1) + blk] = curved14;
          }
        }
        srcPos += 32;
      }
    }
    return out;
  }

  /// 비압축 12 / 14 / 16-bit 베이어 센서 언패킹
  static Uint16List? _decodeUncompressedSensor({
    required Uint8List bytes,
    required List<int> stripOffsets,
    required List<int> stripByteCounts,
    required int width,
    required int height,
    required int bitsPerSample,
    required bool littleEndian,
  }) {
    final totalPixels = width * height;
    final out = Uint16List(totalPixels);
    int outIdx = 0;

    for (int s = 0; s < stripOffsets.length; s++) {
      final off = stripOffsets[s];
      final count = s < stripByteCounts.length ? stripByteCounts[s] : 0;
      if (off <= 0 || count <= 0 || off + count > bytes.length) continue;

      if (bitsPerSample == 16) {
        final end = off + count;
        for (int p = off; p + 1 < end && outIdx < totalPixels; p += 2) {
          out[outIdx++] = littleEndian
              ? (bytes[p] | (bytes[p + 1] << 8))
              : ((bytes[p] << 8) | bytes[p + 1]);
        }
      } else if (bitsPerSample == 14) {
        final end = off + count;
        for (int p = off; p + 6 < end && outIdx + 3 < totalPixels; p += 7) {
          final b0 = bytes[p];
          final b1 = bytes[p + 1];
          final b2 = bytes[p + 2];
          final b3 = bytes[p + 3];
          final b4 = bytes[p + 4];
          final b5 = bytes[p + 5];
          final b6 = bytes[p + 6];
          out[outIdx++] = ((b0 << 6) | (b1 >> 2)) & 0x3FFF;
          out[outIdx++] = (((b1 & 0x03) << 12) | (b2 << 4) | (b3 >> 4)) & 0x3FFF;
          out[outIdx++] = (((b3 & 0x0F) << 10) | (b4 << 2) | (b5 >> 6)) & 0x3FFF;
          out[outIdx++] = (((b5 & 0x3F) << 8) | b6) & 0x3FFF;
        }
      } else if (bitsPerSample == 12) {
        final end = off + count;
        for (int p = off; p + 2 < end && outIdx + 1 < totalPixels; p += 3) {
          final b0 = bytes[p];
          final b1 = bytes[p + 1];
          final b2 = bytes[p + 2];
          out[outIdx++] = ((b0 << 4) | (b1 >> 4)) & 0x0FFF;
          out[outIdx++] = (((b1 & 0x0F) << 8) | b2) & 0x0FFF;
        }
      }
    }

    return outIdx > totalPixels ~/ 2 ? out : null;
  }

  /// 14/16-bit 베이어 배열 → 32-bit 선형 Float RGB 디모자이킹 및 카메라 색행렬 보정
  static ({Float32List linearRgb, Uint8List rgb8, int width, int height})
  _demosaicBayerToFloat32({
    required Uint16List bayer,
    required int rawW,
    required int rawH,
    required List<int> cfa,
    required List<int> blackLevels,
    required int whiteLevel,
    required double wbR,
    required double wbG,
    required double wbB,
  }) {
    // 2x2 베이어 셀 단위로 디모자이크하여 크로마 모아레 없는 깨끗한 32-bit Float 선형 RGB 생성
    // (7040x4688 센서의 경우 3520x2344 고해상도 32-bit Float로 즉시 복원되어 모바일/데스크톱 모두에서 메모리 크래시 없이 초고속 동작)
    final outW = rawW ~/ 2;
    final outH = rawH ~/ 2;
    final linearRgb = Float32List(outW * outH * 3);
    final rgb8 = Uint8List(outW * outH * 3);

    final c00 = cfa[0].clamp(0, 2);
    final c01 = cfa[1].clamp(0, 2);
    final c10 = cfa[2].clamp(0, 2);
    final c11 = cfa[3].clamp(0, 2);

    final bl0 = blackLevels[0].toDouble();
    final bl1 = blackLevels[1].toDouble();
    final bl2 = blackLevels[2].toDouble();
    final bl3 = blackLevels[3].toDouble();
    final scale = 1.0 / math.max(1.0, whiteLevel - bl0);

    // Sony / 표준 카메라 센서 RGB -> 선형 sRGB 색변환 행렬 (LibRaw D65 ColorMatrix와 동일한 R/G/B 밸런스 보장)
    const m00 = 1.52, m01 = -0.42, m02 = -0.10;
    const m10 = -0.16, m11 = 1.30, m12 = -0.14;
    const m20 = -0.03, m21 = -0.19, m22 = 1.22;

    // 65,536 단계 16-bit 선형 -> 8-bit sRGB 고속 LUT 생성
    final srgbLut = Uint8List(65536);
    for (int v = 0; v < 65536; v++) {
      srgbLut[v] = (linearToSrgb(v / 65535.0) * 255.0 + 0.5)
          .floor()
          .clamp(0, 255);
    }

    final chSum = Float64List(3);
    final chCnt = Int32List(3);

    // 우측 끝 약 24픽셀의 센서 옵티컬 블랙(Optical Black) 영역 제외
    final validOutW = outW > 64 ? outW - 12 : outW;
    final outBuf = Float32List(validOutW * outH * 3);
    final outRgb8 = Uint8List(validOutW * outH * 3);

    for (int oy = 0; oy < outH; oy++) {
      final r0 = (oy * 2) * rawW;
      final r1 = r0 + rawW;
      for (int ox = 0; ox < validOutW; ox++) {
        final c0 = ox * 2;
        final v00 = math.max(0.0, (bayer[r0 + c0] - bl0) * scale);
        final v01 = math.max(0.0, (bayer[r0 + c0 + 1] - bl1) * scale);
        final v10 = math.max(0.0, (bayer[r1 + c0] - bl2) * scale);
        final v11 = math.max(0.0, (bayer[r1 + c0 + 1] - bl3) * scale);

        chSum[0] = 0.0;
        chSum[1] = 0.0;
        chSum[2] = 0.0;
        chCnt[0] = 0;
        chCnt[1] = 0;
        chCnt[2] = 0;

        chSum[c00] += v00;
        chCnt[c00]++;
        chSum[c01] += v01;
        chCnt[c01]++;
        chSum[c10] += v10;
        chCnt[c10]++;
        chSum[c11] += v11;
        chCnt[c11]++;

        final camR = (chCnt[0] > 0 ? chSum[0] / chCnt[0] : 0.0) * wbR;
        final camG = (chCnt[1] > 0 ? chSum[1] / chCnt[1] : 0.0) * wbG;
        final camB = (chCnt[2] > 0 ? chSum[2] / chCnt[2] : 0.0) * wbB;

        final linR = (m00 * camR + m01 * camG + m02 * camB).clamp(0.0, 1.0);
        final linG = (m10 * camR + m11 * camG + m12 * camB).clamp(0.0, 1.0);
        final linB = (m20 * camR + m21 * camG + m22 * camB).clamp(0.0, 1.0);

        final dst = (oy * validOutW + ox) * 3;
        outBuf[dst] = linR;
        outBuf[dst + 1] = linG;
        outBuf[dst + 2] = linB;

        outRgb8[dst] = srgbLut[(linR * 65535.0 + 0.5).floor().clamp(0, 65535)];
        outRgb8[dst + 1] =
            srgbLut[(linG * 65535.0 + 0.5).floor().clamp(0, 65535)];
        outRgb8[dst + 2] =
            srgbLut[(linB * 65535.0 + 0.5).floor().clamp(0, 65535)];
      }
    }

    return (
      linearRgb: outBuf,
      rgb8: outRgb8,
      width: validOutW,
      height: outH,
    );
  }

  static ({Float32List linearRgb, Uint8List rgb8, int width, int height})
  _applyOrientationFloat(
    Float32List lin,
    Uint8List rgb8,
    int w,
    int h,
    int orient,
  ) {
    if (orient != 3 && orient != 6 && orient != 8) {
      return (linearRgb: lin, rgb8: rgb8, width: w, height: h);
    }
    final newW = (orient == 6 || orient == 8) ? h : w;
    final newH = (orient == 6 || orient == 8) ? w : h;
    final outLin = Float32List(newW * newH * 3);
    final outRgb8 = Uint8List(newW * newH * 3);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int nx = x, ny = y;
        if (orient == 3) {
          nx = w - 1 - x;
          ny = h - 1 - y;
        } else if (orient == 6) {
          nx = h - 1 - y;
          ny = x;
        } else if (orient == 8) {
          nx = y;
          ny = w - 1 - x;
        }
        final s = (y * w + x) * 3;
        final d = (ny * newW + nx) * 3;
        outLin[d] = lin[s];
        outLin[d + 1] = lin[s + 1];
        outLin[d + 2] = lin[s + 2];
        outRgb8[d] = rgb8[s];
        outRgb8[d + 1] = rgb8[s + 1];
        outRgb8[d + 2] = rgb8[s + 2];
      }
    }
    return (linearRgb: outLin, rgb8: outRgb8, width: newW, height: newH);
  }
}

/// TIFF 및 SubIFD 센서 메타데이터 리더
class _TiffSensorParser {
  final Uint8List b;
  final bool le;
  final int ifd0;
  _TiffSensorParser._(this.b, this.le, this.ifd0);

  static _TiffSensorParser? tryCreate(Uint8List b) {
    if (b.length < 16) return null;
    final isLe = b[0] == 0x49 && b[1] == 0x49;
    final isBe = b[0] == 0x4D && b[1] == 0x4D;
    if (!isLe && !isBe) return null;
    final r = _TiffSensorParser._(b, isLe, 0);
    final magic = r._u16(2);
    if (magic != 42 && magic != 0x55 && magic != 0x4F52) return null;
    final off = r._u32(4);
    if (off <= 0 || off + 2 > b.length) return null;
    return _TiffSensorParser._(b, isLe, off);
  }

  int _u16(int o) {
    if (o < 0 || o + 2 > b.length) return 0;
    return le ? (b[o] | (b[o + 1] << 8)) : ((b[o] << 8) | b[o + 1]);
  }

  int _u32(int o) {
    if (o < 0 || o + 4 > b.length) return 0;
    return le
        ? (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24))
        : ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]);
  }

  int? _entry(int ifdOffset, int tag) {
    if (ifdOffset <= 0 || ifdOffset + 2 > b.length) return null;
    final count = _u16(ifdOffset);
    var p = ifdOffset + 2;
    for (var i = 0; i < count && p + 12 <= b.length; i++, p += 12) {
      if (_u16(p) == tag) return p;
    }
    return null;
  }

  /// 센서 RAW 데이터가 들어 있는 SubIFD 또는 IFD 오프셋 탐색
  int? findSensorRawIfd() {
    final candidates = <int>[ifd0];

    // IFD0의 SubIFDs (0x014A) 수집
    final subOffsets = readIntArrayTag(ifd0, 0x014A);
    candidates.addAll(subOffsets);

    // IFD 체인(Next IFD)도 탐색
    int cur = ifd0;
    for (int step = 0; step < 6; step++) {
      final count = _u16(cur);
      final nextPtr = cur + 2 + count * 12;
      if (nextPtr + 4 > b.length) break;
      final nextIfd = _u32(nextPtr);
      if (nextIfd <= 0 || nextIfd + 2 > b.length) break;
      candidates.add(nextIfd);
      candidates.addAll(readIntArrayTag(nextIfd, 0x014A));
      cur = nextIfd;
    }

    int? bestIfd;
    int bestPixels = 0;
    for (final ifd in candidates) {
      final photo = readIntTag(ifd, 0x0106) ?? 0; // 32803 = CFA
      final comp = readIntTag(ifd, 0x0103) ?? 0; // 32767 = Sony ARW2, 1 = Uncompressed
      final w = readIntTag(ifd, 0x0100) ?? 0;
      final h = readIntTag(ifd, 0x0101) ?? 0;
      if ((photo == 32803 || comp == 32767) && w * h > bestPixels) {
        bestPixels = w * h;
        bestIfd = ifd;
      }
    }
    return bestIfd;
  }

  int? readIntTag(int ifdOffset, int tag) {
    final p = _entry(ifdOffset, tag);
    if (p == null) return null;
    final type = _u16(p + 2);
    if (type == 3) return _u16(p + 8);
    if (type == 4) return _u32(p + 8);
    return _u32(p + 8);
  }

  List<int> readIntArrayTag(int ifdOffset, int tag) {
    final p = _entry(ifdOffset, tag);
    if (p == null) return const [];
    final type = _u16(p + 2);
    final count = _u32(p + 4);
    if (count <= 0 || count > 65536) return const [];
    final elemSize = (type == 3 || type == 8) ? 2 : 4;
    final totalBytes = count * elemSize;
    final valOffset = totalBytes <= 4 ? (p + 8) : _u32(p + 8);
    if (valOffset < 0 || valOffset + totalBytes > b.length) return const [];

    final res = <int>[];
    for (int i = 0; i < count; i++) {
      final pos = valOffset + i * elemSize;
      res.add(elemSize == 2 ? _u16(pos) : _u32(pos));
    }
    return res;
  }

  List<int> readShortArrayTag(int ifdOffset, int tag) {
    final p = _entry(ifdOffset, tag);
    if (p == null) return const [];
    final count = _u32(p + 4);
    if (count <= 0 || count > 1024) return const [];
    final totalBytes = count * 2;
    final valOffset = totalBytes <= 4 ? (p + 8) : _u32(p + 8);
    if (valOffset < 0 || valOffset + totalBytes > b.length) return const [];

    final res = <int>[];
    for (int i = 0; i < count; i++) {
      res.add(_u16(valOffset + i * 2));
    }
    return res;
  }

  List<int> readByteArrayTag(int ifdOffset, int tag) {
    final p = _entry(ifdOffset, tag);
    if (p == null) return const [];
    final count = _u32(p + 4);
    if (count <= 0 || count > 256) return const [];
    final valOffset = count <= 4 ? (p + 8) : _u32(p + 8);
    if (valOffset < 0 || valOffset + count > b.length) return const [];
    return b.sublist(valOffset, valOffset + count);
  }

  int orientation() {
    final v = readIntTag(ifd0, 0x0112) ?? 1;
    return (v >= 1 && v <= 8) ? v : 1;
  }

  String? ascii(int ifdOffset, int tag) {
    final p = _entry(ifdOffset, tag);
    if (p == null) return null;
    final count = _u32(p + 4);
    if (count <= 0 || count > 256) return null;
    final start = count <= 4 ? p + 8 : _u32(p + 8);
    if (start < 0 || start + count > b.length) return null;
    final bytes = b.sublist(start, start + count);
    final end = bytes.indexOf(0);
    return String.fromCharCodes(
      end >= 0 ? bytes.sublist(0, end) : bytes,
    ).trim();
  }
}

// ───────────────────────── 프록시 / 썸네일 (32-bit Float 무손실 유지) ─────────────────────────

/// 영역 평균 다운샘플 (긴 변이 [maxDim] 초과일 때만)
/// - [linearRgb]가 제공되면 32-bit Float 선형 버퍼도 함께 무손실 다운샘플링하여 14/16-bit 다이내믹 레인지 보존
ProxyImage makeProxy(
  Uint8List rgb,
  int w,
  int h,
  int maxDim, [
  Float32List? linearRgb,
]) {
  final longest = math.max(w, h);
  if (longest <= maxDim) return ProxyImage(w, h, rgb, linearRgb);

  final scale = maxDim / longest;
  final nw = math.max(1, (w * scale).round());
  final nh = math.max(1, (h * scale).round());
  final outRgb = Uint8List(nw * nh * 3);
  final outLin = linearRgb != null ? Float32List(nw * nh * 3) : null;

  for (var oy = 0; oy < nh; oy++) {
    final y0 = (oy * h) ~/ nh;
    final y1 = math.max(y0 + 1, ((oy + 1) * h) ~/ nh);
    for (var ox = 0; ox < nw; ox++) {
      final x0 = (ox * w) ~/ nw;
      final x1 = math.max(x0 + 1, ((ox + 1) * w) ~/ nw);
      var r = 0, g = 0, b = 0;
      double lr = 0.0, lg = 0.0, lb = 0.0;
      for (var y = y0; y < y1; y++) {
        var idx = (y * w + x0) * 3;
        for (var x = x0; x < x1; x++) {
          r += rgb[idx];
          g += rgb[idx + 1];
          b += rgb[idx + 2];
          if (linearRgb != null) {
            lr += linearRgb[idx];
            lg += linearRgb[idx + 1];
            lb += linearRgb[idx + 2];
          }
          idx += 3;
        }
      }
      final cnt = (y1 - y0) * (x1 - x0);
      final o = (oy * nw + ox) * 3;
      outRgb[o] = r ~/ cnt;
      outRgb[o + 1] = g ~/ cnt;
      outRgb[o + 2] = b ~/ cnt;
      if (outLin != null) {
        final invCnt = 1.0 / cnt;
        outLin[o] = lr * invCnt;
        outLin[o + 1] = lg * invCnt;
        outLin[o + 2] = lb * invCnt;
      }
    }
  }

  // 고해상도 품질 프록시(maxDim >= 1800) 생성 시:
  // 베이어 디모자이킹 및 박스 다운샘플링 과정에서 손실되는 미세 경계선 선명도(Capture Deconvolution)를
  // 노이즈 증폭 없이 자연스럽게 복원하여 기본 1배율 뷰와 확대 뷰 모두 LightCraft처럼 또렷하게 표시
  if (maxDim >= 1800 && nw >= 64 && nh >= 64) {
    _applyCaptureDeconvolution(outRgb, outLin, nw, nh);
  }

  return ProxyImage(nw, nh, outRgb, outLin);
}

/// 센서 OLPF 및 다운샘플링 소프트니스를 보정하는 미세 휘도 디컨볼루션 (노이즈 임계값 보호 포함)
void _applyCaptureDeconvolution(
  Uint8List rgb,
  Float32List? lin,
  int w,
  int h,
) {
  if (lin != null) {
    final src = Float32List.fromList(lin);
    const double amount = 0.34;
    const double noiseFloor = 0.0012;
    for (int y = 1; y < h - 1; y++) {
      final row = y * w;
      for (int x = 1; x < w - 1; x++) {
        final idx = (row + x) * 3;
        final top = ((row - w) + x) * 3;
        final bot = ((row + w) + x) * 3;
        final lft = idx - 3;
        final rgt = idx + 3;

        final cR = src[idx], cG = src[idx + 1], cB = src[idx + 2];
        final cLum = 0.2126 * cR + 0.7152 * cG + 0.0722 * cB;

        final nR = 0.25 * (src[top] + src[bot] + src[lft] + src[rgt]);
        final nG =
            0.25 * (src[top + 1] + src[bot + 1] + src[lft + 1] + src[rgt + 1]);
        final nB =
            0.25 * (src[top + 2] + src[bot + 2] + src[lft + 2] + src[rgt + 2]);
        final nLum = 0.2126 * nR + 0.7152 * nG + 0.0722 * nB;

        final diff = cLum - nLum;
        if (diff.abs() > noiseFloor && cLum > 0.0005) {
          final boost = (diff * amount) / cLum;
          final factor = (1.0 + boost).clamp(0.75, 1.35);
          lin[idx] = (cR * factor).clamp(0.0, 1.0);
          lin[idx + 1] = (cG * factor).clamp(0.0, 1.0);
          lin[idx + 2] = (cB * factor).clamp(0.0, 1.0);
        }
      }
    }
  } else {
    final src = Uint8List.fromList(rgb);
    const double amount = 0.34;
    for (int y = 1; y < h - 1; y++) {
      final row = y * w;
      for (int x = 1; x < w - 1; x++) {
        final idx = (row + x) * 3;
        final top = ((row - w) + x) * 3;
        final bot = ((row + w) + x) * 3;
        final lft = idx - 3;
        final rgt = idx + 3;

        for (int c = 0; c < 3; c++) {
          final center = src[idx + c];
          final neigh =
              (src[top + c] + src[bot + c] + src[lft + c] + src[rgt + c]) *
                  0.25;
          final diff = center - neigh;
          if (diff.abs() > 2.0) {
            rgb[idx + c] =
                (center + diff * amount).round().clamp(0, 255);
          }
        }
      }
    }
  }
}

/// RGB8 → RGBA8
Uint8List rgbToRgba(ProxyImage p) {
  final n = p.width * p.height;
  final out = Uint8List(n * 4);
  for (var i = 0; i < n; i++) {
    out[i * 4] = p.rgb[i * 3];
    out[i * 4 + 1] = p.rgb[i * 3 + 1];
    out[i * 4 + 2] = p.rgb[i * 3 + 2];
    out[i * 4 + 3] = 255;
  }
  return out;
}
