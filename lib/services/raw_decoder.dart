import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'pipeline_core.dart';

/// 디코딩 완료된 풀 해상도 이미지
class DecodedImage {
  final String name;
  final String path;
  final String ext;
  final int fileSize;
  final int width;
  final int height;
  final bool isRaw;
  final String camera;
  final String note;
  final Uint8List rgb; // sRGB 8-bit RGB (width*height*3)

  DecodedImage({
    required this.name,
    required this.path,
    required this.ext,
    required this.fileSize,
    required this.width,
    required this.height,
    required this.isRaw,
    required this.camera,
    required this.note,
    required this.rgb,
  });
}

const Set<String> kRawExtensions = {
  'arw', 'cr2', 'cr3', 'nef', 'dng', 'raf', 'orf', 'rw2', 'pef', 'srw', 'kdc', 'mos',
};
const Set<String> kImageExtensions = {
  'jpg', 'jpeg', 'png', 'tif', 'tiff', 'bmp', 'webp',
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

/// 파일을 읽어 RGB8 로 디코딩 (백그라운드 Isolate 안에서 호출할 것)
DecodedImage decodeImageFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw Exception('파일을 찾을 수 없습니다: $path');
  }
  final bytes = file.readAsBytesSync();
  final ext = _extOf(path);
  final name = _nameOf(path);

  if (kRawExtensions.contains(ext)) {
    return _decodeRaw(bytes, name, path, ext);
  }

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('지원되지 않거나 손상된 이미지입니다: $name');
  }
  img.Image image = decoded;
  var camera = '';
  try {
    final make = image.exif.imageIfd.make ?? '';
    final model = image.exif.imageIfd.model ?? '';
    camera = '$make $model'.trim();
  } catch (_) {}
  try {
    image = img.bakeOrientation(image);
  } catch (_) {}

  return DecodedImage(
    name: name,
    path: path,
    ext: ext.toUpperCase(),
    fileSize: bytes.length,
    width: image.width,
    height: image.height,
    isRaw: false,
    camera: camera.isEmpty ? '일반 이미지' : camera,
    note: '8-bit 표준 이미지',
    rgb: _toRgbBytes(image),
  );
}

Uint8List _toRgbBytes(img.Image im) {
  final c = (im.numChannels == 3 && im.format == img.Format.uint8)
      ? im
      : im.convert(format: img.Format.uint8, numChannels: 3);
  return c.getBytes(order: img.ChannelOrder.rgb);
}

// ───────────────────────── RAW(카메라 내장 프리뷰) ─────────────────────────

DecodedImage _decodeRaw(Uint8List bytes, String name, String path, String ext) {
  final tiff = _TiffReader.tryCreate(bytes);
  final preview = _largestEmbeddedJpeg(bytes);
  if (preview == null) {
    throw Exception(
      '$name: 내장 JPEG 프리뷰를 찾지 못했습니다.\n'
      '이 형식은 센서 RAW 직접 디코딩(LibRaw)이 필요합니다.',
    );
  }

  var image = preview;
  final orient = tiff?.orientation() ?? 1;
  if (orient == 3) {
    image = img.copyRotate(image, angle: 180);
  } else if (orient == 6) {
    image = img.copyRotate(image, angle: 90);
  } else if (orient == 8) {
    image = img.copyRotate(image, angle: 270);
  }

  final make = tiff?.ascii(0x010F) ?? '';
  final model = tiff?.ascii(0x0110) ?? '';
  final camera = '$make $model'.trim();

  return DecodedImage(
    name: name,
    path: path,
    ext: ext.toUpperCase(),
    fileSize: bytes.length,
    width: image.width,
    height: image.height,
    isRaw: true,
    camera: camera.isEmpty ? '${ext.toUpperCase()} RAW' : camera,
    note: '카메라 내장 JPEG 프리뷰 ${image.width}×${image.height} (센서 RAW 아님)',
    rgb: _toRgbBytes(image),
  );
}

/// 파일 안에서 가장 큰 JPEG(SOI=FF D8 FF)를 O(n) 스캔으로 찾아 디코딩
img.Image? _largestEmbeddedJpeg(Uint8List b) {
  final candidates = <int>[];
  final n = b.length - 3;
  for (var i = 0; i < n; i++) {
    if (b[i] == 0xFF && b[i + 1] == 0xD8 && b[i + 2] == 0xFF) {
      candidates.add(i);
      if (candidates.length >= 64) break;
    }
  }

  var bestOff = -1;
  var bestPixels = 0;
  for (final off in candidates) {
    try {
      final view = Uint8List.sublistView(b, off);
      final info = img.JpegDecoder().startDecode(view);
      if (info == null) continue;
      final px = info.width * info.height;
      if (px > bestPixels) {
        bestPixels = px;
        bestOff = off;
      }
    } catch (_) {}
  }
  if (bestOff < 0) return null;
  try {
    return img.decodeJpg(Uint8List.sublistView(b, bestOff));
  } catch (_) {
    return null;
  }
}

/// IFD0 의 Orientation / Make / Model 만 읽는 최소 TIFF 리더 (ARW, DNG, NEF, CR2 등)
class _TiffReader {
  final Uint8List b;
  final bool le;
  final int ifd0;
  _TiffReader._(this.b, this.le, this.ifd0);

  static _TiffReader? tryCreate(Uint8List b) {
    if (b.length < 16) return null;
    final isLe = b[0] == 0x49 && b[1] == 0x49;
    final isBe = b[0] == 0x4D && b[1] == 0x4D;
    if (!isLe && !isBe) return null;
    final r = _TiffReader._(b, isLe, 0);
    final magic = r._u16(2);
    if (magic != 42 && magic != 0x55 && magic != 0x4F52) return null;
    final off = r._u32(4);
    if (off <= 0 || off + 2 > b.length) return null;
    return _TiffReader._(b, isLe, off);
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

  int? _entry(int tag) {
    final count = _u16(ifd0);
    var p = ifd0 + 2;
    for (var i = 0; i < count && p + 12 <= b.length; i++, p += 12) {
      if (_u16(p) == tag) return p;
    }
    return null;
  }

  int orientation() {
    final p = _entry(0x0112);
    if (p == null) return 1;
    final v = _u16(p + 8);
    return (v >= 1 && v <= 8) ? v : 1;
  }

  String? ascii(int tag) {
    final p = _entry(tag);
    if (p == null) return null;
    final count = _u32(p + 4);
    if (count <= 0 || count > 256) return null;
    final start = count <= 4 ? p + 8 : _u32(p + 8);
    if (start < 0 || start + count > b.length) return null;
    final bytes = b.sublist(start, start + count);
    final end = bytes.indexOf(0);
    return String.fromCharCodes(end >= 0 ? bytes.sublist(0, end) : bytes).trim();
  }
}

// ───────────────────────── 프록시 / 썸네일 ─────────────────────────

/// 영역 평균 다운샘플 (긴 변이 [maxDim] 초과일 때만)
ProxyImage makeProxy(Uint8List rgb, int w, int h, int maxDim) {
  final longest = math.max(w, h);
  if (longest <= maxDim) return ProxyImage(w, h, rgb);

  final scale = maxDim / longest;
  final nw = math.max(1, (w * scale).round());
  final nh = math.max(1, (h * scale).round());
  final out = Uint8List(nw * nh * 3);

  for (var oy = 0; oy < nh; oy++) {
    final y0 = (oy * h) ~/ nh;
    final y1 = math.max(y0 + 1, ((oy + 1) * h) ~/ nh);
    for (var ox = 0; ox < nw; ox++) {
      final x0 = (ox * w) ~/ nw;
      final x1 = math.max(x0 + 1, ((ox + 1) * w) ~/ nw);
      var r = 0, g = 0, b = 0;
      for (var y = y0; y < y1; y++) {
        var idx = (y * w + x0) * 3;
        for (var x = x0; x < x1; x++) {
          r += rgb[idx];
          g += rgb[idx + 1];
          b += rgb[idx + 2];
          idx += 3;
        }
      }
      final cnt = (y1 - y0) * (x1 - x0);
      final o = (oy * nw + ox) * 3;
      out[o] = r ~/ cnt;
      out[o + 1] = g ~/ cnt;
      out[o + 2] = b ~/ cnt;
    }
  }
  return ProxyImage(nw, nh, out);
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
