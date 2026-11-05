import 'dart:io';

/// 사진에 연동된 XMP 사이드카 메타데이터
class XmpData {
  final String xmpPath;
  final bool fileExists;
  int rating; // 0 ~ 5 (0 = 별점 없음)
  String cameraMake;
  String cameraModel;
  String lensModel;
  double? focalLength;
  double? fNumber;

  XmpData({
    required this.xmpPath,
    this.fileExists = false,
    this.rating = 0,
    this.cameraMake = '',
    this.cameraModel = '',
    this.lensModel = '',
    this.focalLength,
    this.fNumber,
  });
}

/// 다크테이블 / 라이트룸 / 카메라RAW 표준 XMP 사이드카 연동 서비스
class XmpService {
  /// 사진 파일 경로에 대응하는 XMP 사이드카 파일 탐색
  /// - 1순위: <파일명>.xmp (예: 7M401154.xmp)
  /// - 2순위: <파일명.확장자>.xmp (예: 7M401154.ARW.xmp — 다크테이블 표준)
  static String resolveXmpPath(String photoPath) {
    final lastDot = photoPath.lastIndexOf('.');
    final withoutExt =
        lastDot != -1 ? photoPath.substring(0, lastDot) : photoPath;
    final candidate1 = '$withoutExt.xmp';
    final candidate2 = '$photoPath.xmp';

    if (File(candidate1).existsSync()) return candidate1;
    if (File(candidate2).existsSync()) return candidate2;
    return candidate1; // 없으면 기본 1순위 경로 반환 (신규 생성용)
  }

  /// XMP 사이드카 파일에서 별점(Rating: 0~5), 렌즈 정보, 카메라 정보 파싱
  static Future<XmpData> loadXmp(String photoPath) async {
    final xmpPath = resolveXmpPath(photoPath);
    final file = File(xmpPath);
    if (!file.existsSync()) {
      return XmpData(xmpPath: xmpPath, fileExists: false, rating: 0);
    }

    try {
      final xml = await file.readAsString();
      var rating = 0;
      var cameraMake = '';
      var cameraModel = '';
      var lensModel = '';
      double? focalLength;
      double? fNumber;

      // 1. 별점 (xmp:Rating="2" 또는 <xmp:Rating>2</xmp:Rating>)
      final ratingAttr =
          RegExp(r'''xmp:Rating\s*=\s*["'](\d+)["']''').firstMatch(xml);
      final ratingTag =
          RegExp(r'''<xmp:Rating>(\d+)</xmp:Rating>''').firstMatch(xml);
      if (ratingAttr != null) {
        rating = int.tryParse(ratingAttr.group(1)!) ?? 0;
      } else if (ratingTag != null) {
        rating = int.tryParse(ratingTag.group(1)!) ?? 0;
      }

      // 2. 렌즈 모델명 (exifEX:LensModel="...", aux:Lens="...", <exifEX:LensModel>...)
      final lens1 =
          RegExp(r'''exifEX:LensModel\s*=\s*["']([^"']+)["']''').firstMatch(xml);
      final lens2 =
          RegExp(r'''aux:Lens\s*=\s*["']([^"']+)["']''').firstMatch(xml);
      final lens3 =
          RegExp(r'''<exifEX:LensModel>([^<]+)</exifEX:LensModel>''').firstMatch(xml);
      final lens4 =
          RegExp(r'''<aux:Lens>([^<]+)</aux:Lens>''').firstMatch(xml);

      if (lens1 != null) {
        lensModel = lens1.group(1)!.trim();
      } else if (lens2 != null) {
        lensModel = lens2.group(1)!.trim();
      } else if (lens3 != null) {
        lensModel = lens3.group(1)!.trim();
      } else if (lens4 != null) {
        lensModel = lens4.group(1)!.trim();
      }

      // 3. 카메라 바디 (tiff:Model, tiff:Make)
      final modelMatch =
          RegExp(r'''tiff:Model\s*=\s*["']([^"']+)["']''').firstMatch(xml);
      final makeMatch =
          RegExp(r'''tiff:Make\s*=\s*["']([^"']+)["']''').firstMatch(xml);
      if (modelMatch != null) cameraModel = modelMatch.group(1)!.trim();
      if (makeMatch != null) cameraMake = makeMatch.group(1)!.trim();

      // 4. 초점거리 & 조리개
      final focalMatch =
          RegExp(r'''exif:FocalLength\s*=\s*["'](\d+)(?:/(\d+))?["']''')
              .firstMatch(xml);
      if (focalMatch != null) {
        final n = double.tryParse(focalMatch.group(1) ?? '') ?? 0.0;
        final d = double.tryParse(focalMatch.group(2) ?? '1') ?? 1.0;
        if (d > 0) focalLength = n / d;
      }

      final fNumMatch =
          RegExp(r'''exif:FNumber\s*=\s*["'](\d+)(?:/(\d+))?["']''')
              .firstMatch(xml);
      if (fNumMatch != null) {
        final n = double.tryParse(fNumMatch.group(1) ?? '') ?? 0.0;
        final d = double.tryParse(fNumMatch.group(2) ?? '1') ?? 1.0;
        if (d > 0) fNumber = n / d;
      }

      return XmpData(
        xmpPath: xmpPath,
        fileExists: true,
        rating: rating.clamp(0, 5),
        cameraMake: cameraMake,
        cameraModel: cameraModel,
        lensModel: lensModel,
        focalLength: focalLength,
        fNumber: fNumber,
      );
    } catch (_) {
      return XmpData(xmpPath: xmpPath, fileExists: false, rating: 0);
    }
  }

  /// 동기식 로드 버전 (Isolate/백그라운드 디코딩 중 즉시 호출용)
  static XmpData loadXmpSync(String photoPath) {
    final xmpPath = resolveXmpPath(photoPath);
    final file = File(xmpPath);
    if (!file.existsSync()) {
      return XmpData(xmpPath: xmpPath, fileExists: false, rating: 0);
    }

    try {
      final xml = file.readAsStringSync();
      var rating = 0;
      var cameraMake = '';
      var cameraModel = '';
      var lensModel = '';
      double? focalLength;
      double? fNumber;

      final ratingAttr =
          RegExp(r'''xmp:Rating\s*=\s*["'](\d+)["']''').firstMatch(xml);
      final ratingTag =
          RegExp(r'''<xmp:Rating>(\d+)</xmp:Rating>''').firstMatch(xml);
      if (ratingAttr != null) {
        rating = int.tryParse(ratingAttr.group(1)!) ?? 0;
      } else if (ratingTag != null) {
        rating = int.tryParse(ratingTag.group(1)!) ?? 0;
      }

      final lens1 =
          RegExp(r'''exifEX:LensModel\s*=\s*["']([^"']+)["']''').firstMatch(xml);
      final lens2 =
          RegExp(r'''aux:Lens\s*=\s*["']([^"']+)["']''').firstMatch(xml);
      final lens3 =
          RegExp(r'''<exifEX:LensModel>([^<]+)</exifEX:LensModel>''').firstMatch(xml);
      final lens4 =
          RegExp(r'''<aux:Lens>([^<]+)</aux:Lens>''').firstMatch(xml);

      if (lens1 != null) {
        lensModel = lens1.group(1)!.trim();
      } else if (lens2 != null) {
        lensModel = lens2.group(1)!.trim();
      } else if (lens3 != null) {
        lensModel = lens3.group(1)!.trim();
      } else if (lens4 != null) {
        lensModel = lens4.group(1)!.trim();
      }

      final modelMatch =
          RegExp(r'''tiff:Model\s*=\s*["']([^"']+)["']''').firstMatch(xml);
      final makeMatch =
          RegExp(r'''tiff:Make\s*=\s*["']([^"']+)["']''').firstMatch(xml);
      if (modelMatch != null) cameraModel = modelMatch.group(1)!.trim();
      if (makeMatch != null) cameraMake = makeMatch.group(1)!.trim();

      final focalMatch =
          RegExp(r'''exif:FocalLength\s*=\s*["'](\d+)(?:/(\d+))?["']''')
              .firstMatch(xml);
      if (focalMatch != null) {
        final n = double.tryParse(focalMatch.group(1) ?? '') ?? 0.0;
        final d = double.tryParse(focalMatch.group(2) ?? '1') ?? 1.0;
        if (d > 0) focalLength = n / d;
      }

      final fNumMatch =
          RegExp(r'''exif:FNumber\s*=\s*["'](\d+)(?:/(\d+))?["']''')
              .firstMatch(xml);
      if (fNumMatch != null) {
        final n = double.tryParse(fNumMatch.group(1) ?? '') ?? 0.0;
        final d = double.tryParse(fNumMatch.group(2) ?? '1') ?? 1.0;
        if (d > 0) fNumber = n / d;
      }

      return XmpData(
        xmpPath: xmpPath,
        fileExists: true,
        rating: rating.clamp(0, 5),
        cameraMake: cameraMake,
        cameraModel: cameraModel,
        lensModel: lensModel,
        focalLength: focalLength,
        fNumber: fNumber,
      );
    } catch (_) {
      return XmpData(xmpPath: xmpPath, fileExists: false, rating: 0);
    }
  }

  /// 별점(Rating: 0~5)을 XMP 사이드카 파일에 즉시 저장/갱신
  /// - 기존 XMP 파일이 존재하면 내용 및 원본 메타데이터를 보존하면서 xmp:Rating 속성만 교체
  /// - XMP 파일이 없으면 표준 호환 XMP 사이드카 파일 자동 생성
  static Future<bool> saveRating({
    required String photoPath,
    required int rating,
  }) async {
    final clamped = rating.clamp(0, 5);
    final xmpPath = resolveXmpPath(photoPath);
    final file = File(xmpPath);

    try {
      if (await file.exists()) {
        var content = await file.readAsString();
        final attrRegex = RegExp(r'''xmp:Rating\s*=\s*["'](\d+)["']''');
        final tagRegex = RegExp(r'''<xmp:Rating>(\d+)</xmp:Rating>''');

        if (attrRegex.hasMatch(content)) {
          content = content.replaceFirst(attrRegex, 'xmp:Rating="$clamped"');
        } else if (tagRegex.hasMatch(content)) {
          content =
              content.replaceFirst(tagRegex, '<xmp:Rating>$clamped</xmp:Rating>');
        } else {
          // Description 태그 안에 xmp:Rating 속성 삽입
          final descRegex =
              RegExp(r'''(<rdf:Description\b[^>]*?)(\s*/?>)''', dotAll: true);
          final match = descRegex.firstMatch(content);
          if (match != null) {
            final before = match.group(1)!;
            final closing = match.group(2)!;
            content = content.replaceFirst(
                descRegex, '$before\n    xmp:Rating="$clamped"$closing');
          }
        }
        await file.writeAsString(content);
        return true;
      } else {
        // 신규 XMP 사이드카 생성
        final newXmp = '''<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
    xmp:Rating="$clamped"/>
 </rdf:RDF>
</x:xmpmeta>
''';
        await file.writeAsString(newXmp);
        return true;
      }
    } catch (e) {
      return false;
    }
  }
}
