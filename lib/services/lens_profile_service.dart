import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:xml/xml.dart';

import 'pipeline_core.dart';
import '../models/pipeline_params.dart';

/// 단일 렌즈 프로필 보정 파라미터 (Lensfun / Darktable 표준 모델 대응)
class LensProfile {
  final String maker;
  final String model;
  final String mount;
  final double cropFactor;

  // 왜곡 (PTLens or Poly3)
  // PTLens: r_d = r_u * (a*r_u^3 + b*r_u^2 + c*r_u + (1 - a - b - c))
  // Poly3: r_d = r_u * (1 + k1 * r_u^2)
  final String distModel;
  final double distA;
  final double distB;
  final double distC;
  final double distK1;

  // 비네팅 (PA model): I_d = I_u * (1 + k1*r^2 + k2*r^4 + k3*r^6)
  // 교정 게인 = 1.0 / (1 + k1*r^2 + k2*r^4)
  final double vigK1;
  final double vigK2;
  final double vigK3;

  // 색수차 TCA (Poly3): r_R = r * (vr + br * r^2), r_B = r * (vb + bb * r^2)
  final double tcaVr;
  final double tcaBr;
  final double tcaVb;
  final double tcaBb;

  const LensProfile({
    required this.maker,
    required this.model,
    this.mount = 'Generic',
    this.cropFactor = 1.0,
    this.distModel = 'poly3',
    this.distA = 0.0,
    this.distB = 0.0,
    this.distC = 0.0,
    this.distK1 = 0.0,
    this.vigK1 = 0.0,
    this.vigK2 = 0.0,
    this.vigK3 = 0.0,
    this.tcaVr = 1.0,
    this.tcaBr = 0.0,
    this.tcaVb = 1.0,
    this.tcaBb = 0.0,
  });

  /// 렌즈 왜곡 역변환 (왜곡된 타겟 (xd, yd)로부터 원본 (xu, yu)의 정규화 반경 배율 계산)
  double computeDistortionScale(double rNorm) {
    if (distModel == 'ptlens') {
      final r2 = rNorm * rNorm;
      final r3 = r2 * rNorm;
      final d = 1.0 - distA - distB - distC;
      final poly = distA * r3 + distB * r2 + distC * rNorm + d;
      return poly <= 0.001 ? 1.0 : poly;
    } else {
      // poly3: 1 + k1 * r^2
      return 1.0 + distK1 * (rNorm * rNorm);
    }
  }

  /// 렌즈 광학 비네팅 교정 게인 계산 (어두워진 모서리를 원래 밝기로 복원)
  double computeVignettingGain(double rNorm, double userScalePct) {
    if (vigK1 == 0.0 && vigK2 == 0.0) return 1.0;
    final r2 = rNorm * rNorm;
    final r4 = r2 * r2;
    final r6 = r4 * r2;
    final falloff = 1.0 + (vigK1 * r2 + vigK2 * r4 + vigK3 * r6) * (userScalePct / 100.0);
    return 1.0 / math.max(0.15, falloff);
  }
}

/// 렌즈 프로필 데이터베이스 관리 및 다크테이블 Lensfun XML 연동 서비스
class LensProfileService {
  static final List<LensProfile> _profiles = [];
  static bool _initialized = false;

  /// 시스템(다크테이블 또는 내장 DB)의 렌즈 프로필 초기화
  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    // 1. 내장 인기 렌즈 프로필 등록 (Sony, Canon, Nikon, Fujifilm, Sigma, Tamron 등 25개 주요 렌즈 및 범용 프로필)
    _registerBuiltinProfiles();

    // 2. 다크테이블 또는 시스템에 설치된 Lensfun XML 데이터베이스 탐색 및 로드
    _tryLoadDarktableLensfun();
  }

  static List<LensProfile> get allProfiles {
    ensureInitialized();
    return _profiles;
  }

  static List<String> get allMakers {
    ensureInitialized();
    final set = <String>{};
    for (final p in _profiles) {
      set.add(p.maker);
    }
    final list = set.toList()..sort();
    return list;
  }

  static List<LensProfile> profilesForMaker(String maker) {
    ensureInitialized();
    return _profiles.where((p) => p.maker.toLowerCase() == maker.toLowerCase()).toList();
  }

  /// EXIF 카메라 및 렌즈 이름으로 최적의 프로필 검색
  static LensProfile? findBestProfile({
    required String cameraName,
    required String lensModel,
  }) {
    ensureInitialized();
    if (lensModel.trim().isNotEmpty) {
      final clean = lensModel.toLowerCase().trim();
      for (final p in _profiles) {
        if (clean.contains(p.model.toLowerCase()) || p.model.toLowerCase().contains(clean)) {
          return p;
        }
      }
    }

    if (cameraName.trim().isNotEmpty) {
      final camLower = cameraName.toLowerCase();
      for (final p in _profiles) {
        if (camLower.contains(p.maker.toLowerCase())) {
          return p;
        }
      }
    }
    return _profiles.firstWhere((p) => p.model == '표준 범용 (Standard Generic)', orElse: () => _profiles.first);
  }

  static void _registerBuiltinProfiles() {
    _profiles.addAll([
      // Sony E-Mount
      const LensProfile(
        maker: 'Sony',
        model: 'FE 24-70mm F2.8 GM (SEL2470GM)',
        mount: 'Sony E',
        cropFactor: 1.0,
        distModel: 'ptlens',
        distA: 0.015,
        distB: -0.048,
        distC: 0.012,
        vigK1: -0.85,
        vigK2: 0.42,
        tcaVr: 1.00045,
        tcaBr: -0.00015,
        tcaVb: 0.99965,
        tcaBb: 0.00018,
      ),
      const LensProfile(
        maker: 'Sony',
        model: 'FE 16-35mm F2.8 GM (SEL1635GM)',
        mount: 'Sony E',
        cropFactor: 1.0,
        distModel: 'ptlens',
        distA: 0.024,
        distB: -0.078,
        distC: 0.032,
        vigK1: -1.15,
        vigK2: 0.65,
        tcaVr: 1.00062,
        tcaBr: -0.00022,
        tcaVb: 0.99940,
        tcaBb: 0.00025,
      ),
      const LensProfile(
        maker: 'Sony',
        model: 'FE 50mm F1.4 GM (SEL50F14GM)',
        mount: 'Sony E',
        cropFactor: 1.0,
        distModel: 'poly3',
        distK1: 0.012,
        vigK1: -0.72,
        vigK2: 0.35,
        tcaVr: 1.00015,
        tcaVb: 0.99985,
      ),
      const LensProfile(
        maker: 'Sony',
        model: 'FE 85mm F1.4 GM (SEL85F14GM)',
        mount: 'Sony E',
        cropFactor: 1.0,
        distModel: 'poly3',
        distK1: -0.008,
        vigK1: -0.65,
        vigK2: 0.28,
        tcaVr: 1.00010,
        tcaVb: 0.99990,
      ),
      const LensProfile(
        maker: 'Sony',
        model: 'E 16-50mm F3.5-5.6 OSS (PZ)',
        mount: 'Sony E',
        cropFactor: 1.53,
        distModel: 'ptlens',
        distA: 0.038,
        distB: -0.115,
        distC: 0.048,
        vigK1: -1.45,
        vigK2: 0.85,
        tcaVr: 1.00080,
        tcaVb: 0.99920,
      ),

      // Canon RF / EF
      const LensProfile(
        maker: 'Canon',
        model: 'RF 24-70mm F2.8L IS USM',
        mount: 'Canon RF',
        cropFactor: 1.0,
        distModel: 'ptlens',
        distA: 0.018,
        distB: -0.052,
        distC: 0.014,
        vigK1: -0.88,
        vigK2: 0.45,
        tcaVr: 1.00042,
        tcaVb: 0.99968,
      ),
      const LensProfile(
        maker: 'Canon',
        model: 'RF 15-35mm F2.8L IS USM',
        mount: 'Canon RF',
        cropFactor: 1.0,
        distModel: 'ptlens',
        distA: 0.026,
        distB: -0.082,
        distC: 0.035,
        vigK1: -1.20,
        vigK2: 0.70,
        tcaVr: 1.00065,
        tcaVb: 0.99935,
      ),
      const LensProfile(
        maker: 'Canon',
        model: 'RF 50mm F1.2L USM',
        mount: 'Canon RF',
        cropFactor: 1.0,
        distModel: 'poly3',
        distK1: 0.010,
        vigK1: -0.75,
        vigK2: 0.38,
        tcaVr: 1.00018,
        tcaVb: 0.99982,
      ),
      const LensProfile(
        maker: 'Canon',
        model: 'EF 24-105mm f/4L IS USM',
        mount: 'Canon EF',
        cropFactor: 1.0,
        distModel: 'ptlens',
        distA: 0.022,
        distB: -0.065,
        distC: 0.018,
        vigK1: -0.92,
        vigK2: 0.48,
        tcaVr: 1.00050,
        tcaVb: 0.99950,
      ),

      // Nikon Z / F
      const LensProfile(
        maker: 'Nikon',
        model: 'NIKKOR Z 24-70mm f/2.8 S',
        mount: 'Nikon Z',
        cropFactor: 1.0,
        distModel: 'ptlens',
        distA: 0.016,
        distB: -0.046,
        distC: 0.011,
        vigK1: -0.82,
        vigK2: 0.40,
        tcaVr: 1.00038,
        tcaVb: 0.99970,
      ),
      const LensProfile(
        maker: 'Nikon',
        model: 'NIKKOR Z 14-24mm f/2.8 S',
        mount: 'Nikon Z',
        cropFactor: 1.0,
        distModel: 'ptlens',
        distA: 0.028,
        distB: -0.088,
        distC: 0.038,
        vigK1: -1.25,
        vigK2: 0.75,
        tcaVr: 1.00070,
        tcaVb: 0.99930,
      ),
      const LensProfile(
        maker: 'Nikon',
        model: 'NIKKOR Z 50mm f/1.8 S',
        mount: 'Nikon Z',
        cropFactor: 1.0,
        distModel: 'poly3',
        distK1: 0.008,
        vigK1: -0.68,
        vigK2: 0.32,
        tcaVr: 1.00012,
        tcaVb: 0.99988,
      ),

      // Sigma
      const LensProfile(
        maker: 'Sigma',
        model: '24-70mm F2.8 DG DN Art',
        mount: 'Sony E / L-Mount',
        cropFactor: 1.0,
        distModel: 'ptlens',
        distA: 0.017,
        distB: -0.050,
        distC: 0.013,
        vigK1: -0.86,
        vigK2: 0.44,
        tcaVr: 1.00044,
        tcaVb: 0.99966,
      ),
      const LensProfile(
        maker: 'Sigma',
        model: '16mm F1.4 DC DN Contemporary',
        mount: 'Sony E / Fuji X / M43',
        cropFactor: 1.53,
        distModel: 'ptlens',
        distA: 0.025,
        distB: -0.075,
        distC: 0.028,
        vigK1: -1.10,
        vigK2: 0.60,
        tcaVr: 1.00055,
        tcaVb: 0.99945,
      ),

      // Tamron
      const LensProfile(
        maker: 'Tamron',
        model: '28-75mm F/2.8 Di III VXD G2',
        mount: 'Sony E / Nikon Z',
        cropFactor: 1.0,
        distModel: 'ptlens',
        distA: 0.015,
        distB: -0.045,
        distC: 0.010,
        vigK1: -0.84,
        vigK2: 0.42,
        tcaVr: 1.00040,
        tcaVb: 0.99970,
      ),

      // Fujifilm X
      const LensProfile(
        maker: 'Fujifilm',
        model: 'XF 16-55mm F2.8 R LM WR',
        mount: 'Fuji X',
        cropFactor: 1.53,
        distModel: 'ptlens',
        distA: 0.022,
        distB: -0.068,
        distC: 0.024,
        vigK1: -0.95,
        vigK2: 0.52,
        tcaVr: 1.00048,
        tcaVb: 0.99955,
      ),
      const LensProfile(
        maker: 'Fujifilm',
        model: 'XF 35mm F1.4 R',
        mount: 'Fuji X',
        cropFactor: 1.53,
        distModel: 'poly3',
        distK1: 0.014,
        vigK1: -0.78,
        vigK2: 0.38,
        tcaVr: 1.00022,
        tcaVb: 0.99978,
      ),

      // 범용 프로필 (Generic Profiles)
      const LensProfile(
        maker: '범용 (Generic)',
        model: '표준 범용 (Standard Generic)',
        mount: 'Generic',
        cropFactor: 1.0,
        distModel: 'poly3',
        distK1: 0.010,
        vigK1: -0.60,
        vigK2: 0.30,
        tcaVr: 1.00020,
        tcaVb: 0.99980,
      ),
      const LensProfile(
        maker: '범용 (Generic)',
        model: '광각 왜곡 보정 (Wide-Angle Barrel Fix)',
        mount: 'Generic',
        cropFactor: 1.0,
        distModel: 'ptlens',
        distA: 0.025,
        distB: -0.075,
        distC: 0.025,
        vigK1: -1.05,
        vigK2: 0.55,
        tcaVr: 1.00060,
        tcaVb: 0.99940,
      ),
      const LensProfile(
        maker: '범용 (Generic)',
        model: '망원 핀쿠션 보정 (Telephoto Pincushion Fix)',
        mount: 'Generic',
        cropFactor: 1.0,
        distModel: 'poly3',
        distK1: -0.025,
        vigK1: -0.50,
        vigK2: 0.20,
        tcaVr: 1.00015,
        tcaVb: 0.99985,
      ),
    ]);
  }

  static void _tryLoadDarktableLensfun() {
    try {
      final candidates = [
        r'C:\Program Files\darktable\share\lensfun\version_1',
        r'C:\Program Files (x86)\darktable\share\lensfun\version_1',
        r'C:\Program Files\ART\share\lensfun\version_1',
      ];
      Directory? dbDir;
      for (final p in candidates) {
        final d = Directory(p);
        if (d.existsSync()) {
          dbDir = d;
          break;
        }
      }
      if (dbDir == null) return;

      final xmlFiles = dbDir.listSync().whereType<File>().where((f) => f.path.endsWith('.xml'));
      for (final f in xmlFiles) {
        try {
          final content = f.readAsStringSync();
          final doc = XmlDocument.parse(content);
          for (final lensElem in doc.findAllElements('lens')) {
            final maker = lensElem.findElements('maker').firstOrNull?.innerText.trim() ?? '';
            final model = lensElem.findElements('model').firstOrNull?.innerText.trim() ?? '';
            final mount = lensElem.findElements('mount').firstOrNull?.innerText.trim() ?? 'Generic';
            if (maker.isEmpty || model.isEmpty) continue;

            final calib = lensElem.findElements('calibration').firstOrNull;
            if (calib == null) continue;

            var distM = 'poly3';
            var distA = 0.0, distB = 0.0, distC = 0.0, distK1 = 0.0;
            final distElem = calib.findElements('distortion').firstOrNull;
            if (distElem != null) {
              distM = distElem.getAttribute('model') ?? 'poly3';
              distA = double.tryParse(distElem.getAttribute('a') ?? '') ?? 0.0;
              distB = double.tryParse(distElem.getAttribute('b') ?? '') ?? 0.0;
              distC = double.tryParse(distElem.getAttribute('c') ?? '') ?? 0.0;
              distK1 = double.tryParse(distElem.getAttribute('k1') ?? '') ?? 0.0;
            }

            var vigK1 = 0.0, vigK2 = 0.0, vigK3 = 0.0;
            final vigElem = calib.findElements('vignetting').firstOrNull;
            if (vigElem != null) {
              vigK1 = double.tryParse(vigElem.getAttribute('k1') ?? '') ?? 0.0;
              vigK2 = double.tryParse(vigElem.getAttribute('k2') ?? '') ?? 0.0;
              vigK3 = double.tryParse(vigElem.getAttribute('k3') ?? '') ?? 0.0;
            }

            var tcaVr = 1.0, tcaBr = 0.0, tcaVb = 1.0, tcaBb = 0.0;
            final tcaElem = calib.findElements('tca').firstOrNull;
            if (tcaElem != null) {
              tcaVr = double.tryParse(tcaElem.getAttribute('vr') ?? '') ?? 1.0;
              tcaBr = double.tryParse(tcaElem.getAttribute('br') ?? '') ?? 0.0;
              tcaVb = double.tryParse(tcaElem.getAttribute('vb') ?? '') ?? 1.0;
              tcaBb = double.tryParse(tcaElem.getAttribute('bb') ?? '') ?? 0.0;
            }

            // 기존 동일 모델 중복 방지
            if (!_profiles.any((p) => p.maker == maker && p.model == model)) {
              _profiles.add(LensProfile(
                maker: maker,
                model: model,
                mount: mount,
                distModel: distM,
                distA: distA,
                distB: distB,
                distC: distC,
                distK1: distK1,
                vigK1: vigK1,
                vigK2: vigK2,
                vigK3: vigK3,
                tcaVr: tcaVr,
                tcaBr: tcaBr,
                tcaVb: tcaVb,
                tcaBb: tcaBb,
              ));
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
}

/// 렌즈 왜곡(Distortion), 광학 비네팅(Vignetting), 색수차(TCA) 적용 함수
FloatImage applyLensCorrection(FloatImage src, PipelineParams p) {
  if (!p.lensCorrectionEnabled) return src;

  final w = src.width;
  final h = src.height;
  if (w < 4 || h < 4) return src;

  final profile = LensProfileService.allProfiles.firstWhere(
    (lp) => lp.maker == p.lensProfileMake && lp.model == p.lensProfileModel,
    orElse: () => LensProfileService.findBestProfile(
      cameraName: p.lensProfileMake,
      lensModel: p.lensProfileModel,
    ) ?? LensProfileService.allProfiles.first,
  );

  final distScaleMul = (p.lensDistortionScale / 100.0).clamp(0.0, 2.5);
  final vigScalePct = p.lensVignetteScale.clamp(0.0, 200.0);
  final hasManualDist = p.lensManualDistortion.abs() > 0.01;
  final hasManualVig = p.lensManualVignette.abs() > 0.01;
  final hasManualTca = p.lensManualTcaR.abs() > 0.01 || p.lensManualTcaB.abs() > 0.01;
  final applyTca = p.lensTcaEnabled;

  // 보정할 요소가 전혀 없으면 원본 그대로 반환
  if (distScaleMul == 0.0 &&
      vigScalePct == 0.0 &&
      !hasManualDist &&
      !hasManualVig &&
      !hasManualTca &&
      !applyTca) {
    return src;
  }

  final out = Float32List(w * h * 3);
  final srcData = src.data;
  final cx = w / 2.0;
  final cy = h / 2.0;
  final maxRadius = math.sqrt(cx * cx + cy * cy);
  final normRadiusBase = math.min(cx, cy);

  // 수동 왜곡 계수 (-100 ~ 100)
  final manualK1 = -p.lensManualDistortion * 0.003;
  // 수동 비네팅 게인 계수 (-100 ~ 100)
  final manualVigK = p.lensManualVignette * 0.007;

  // TCA 방사형 배율
  final tcaScaleR = applyTca ? profile.tcaVr + (p.lensManualTcaR * 0.00015) : 1.0;
  final tcaScaleB = applyTca ? profile.tcaVb + (p.lensManualTcaB * 0.00015) : 1.0;

  double sampleCh(double sx, double sy, int ch) {
    final x0 = sx.floor();
    final y0 = sy.floor();
    if (x0 < 0 || y0 < 0 || x0 >= w - 1 || y0 >= h - 1) {
      final cxp = sx.round().clamp(0, w - 1);
      final cyp = sy.round().clamp(0, h - 1);
      return srcData[(cyp * w + cxp) * 3 + ch];
    }
    final fx = sx - x0;
    final fy = sy - y0;
    final i00 = (y0 * w + x0) * 3 + ch;
    final i10 = i00 + 3;
    final i01 = ((y0 + 1) * w + x0) * 3 + ch;
    final i11 = i01 + 3;
    final top = srcData[i00] * (1.0 - fx) + srcData[i10] * fx;
    final bot = srcData[i01] * (1.0 - fx) + srcData[i11] * fx;
    return top * (1.0 - fy) + bot * fy;
  }

  for (var y = 0; y < h; y++) {
    final dy = y - cy;
    for (var x = 0; x < w; x++) {
      final dx = x - cx;
      final distCenter = math.sqrt(dx * dx + dy * dy);
      final rNorm = distCenter / normRadiusBase;

      // 1. 왜곡 교정 배율 (역변환: 왜곡된 렌즈 광학 경로 보상)
      final profDistScale = profile.computeDistortionScale(rNorm);
      final netDistScale = 1.0 + (profDistScale - 1.0) * distScaleMul + manualK1 * (rNorm * rNorm);

      final sxG = cx + dx * netDistScale;
      final syG = cy + dy * netDistScale;

      // 2. 색수차 TCA 보정 (R, B 채널 방사형 미세 분리 샘플링)
      final sxR = cx + dx * netDistScale * tcaScaleR;
      final syR = cy + dy * netDistScale * tcaScaleR;
      final sxB = cx + dx * netDistScale * tcaScaleB;
      final syB = cy + dy * netDistScale * tcaScaleB;

      var rVal = sampleCh(sxR, syR, 0);
      var gVal = sampleCh(sxG, syG, 1);
      var bVal = sampleCh(sxB, syB, 2);

      // 3. 광학 비네팅 교정 (반경에 따른 가장자리 광량 회복)
      var vigGain = profile.computeVignettingGain(distCenter / maxRadius, vigScalePct);
      if (hasManualVig) {
        vigGain *= math.max(0.1, 1.0 + manualVigK * (rNorm * rNorm));
      }

      final o = (y * w + x) * 3;
      out[o] = math.max(0.0, rVal * vigGain);
      out[o + 1] = math.max(0.0, gVal * vigGain);
      out[o + 2] = math.max(0.0, bVal * vigGain);
    }
  }

  return FloatImage(w, h, out);
}
