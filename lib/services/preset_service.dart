import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/pipeline_params.dart';

/// SemiDarktable의 BUILTIN_PRESETS 및 사용자 프리셋 관리 서비스
/// - Vivid Landscape, Warm Portrait 제거
/// - 기존 내장 프리셋도 사용자가 원할 때 삭제(영구 숨김)할 수 있도록 지원
class PresetService {
  static const String _deletedBuiltinsFileName = '_deleted_builtins.json';

  /// 기본 내장 프리셋 (Default, Modern Film, Cinematic Moody, B&W Fine Art)
  static final Map<String, Map<String, dynamic>> builtinPresets = {
    '🔄 Default (초기화)': {},
    '🎞️ Modern Film (필름)': {
      'exposure_enabled': true,
      'exp_black_level': -0.025,
      'exp_contrast': 0.08,
      'sigmoid_enabled': true,
      'sig_contrast': 1.35,
      'sig_toe': 0.18,
      'sig_shoulder': 0.15,
      'tone_curve_enabled': true,
      'tone_curve_points': {
        'rgb': [
          [0.0, 0.05],
          [0.25, 0.22],
          [0.75, 0.78],
          [1.0, 0.96],
        ],
        'r': [
          [0.0, 0.0],
          [1.0, 1.0],
        ],
        'g': [
          [0.0, 0.0],
          [1.0, 1.0],
        ],
        'b': [
          [0.0, 0.03],
          [1.0, 0.97],
        ],
      },
      'color_zones_enabled': true,
      'sat_global': -0.12,
      'sat_vibrance': 0.15,
      'grain_enabled': true,
      'gr_amount': 0.18,
      'vignette_enabled': true,
      'vg_amount': -0.35,
    },
    '🎬 Cinematic Moody (시네마틱)': {
      'exposure_enabled': true,
      'exp_ev': -0.15,
      'exp_contrast': 0.18,
      'sigmoid_enabled': true,
      'sig_contrast': 1.6,
      'sig_toe': 0.25,
      'color_balance_enabled': true,
      'cb_shadows_r': -0.15,
      'cb_midtones_g': 0.05,
      'cb_midtones_b': -0.15,
      'cb_highlights_r': 0.18,
      'color_zones_enabled': true,
      'sat_global': -0.20,
      'sat_vibrance': 0.10,
      'vignette_enabled': true,
      'vg_amount': -0.5,
      'grain_enabled': true,
      'gr_amount': 0.14,
    },
    '🖤 B&W Fine Art (흑백)': {
      'exposure_enabled': true,
      'exp_contrast': 0.28,
      'sigmoid_enabled': true,
      'sig_contrast': 1.8,
      'tone_equalizer_enabled': true,
      'te_blacks': -0.25,
      'te_shadows': -0.15,
      'te_highlights': 0.2,
      'te_whites': 0.15,
      'color_zones_enabled': true,
      'sat_global': -1.0,
      'sat_vibrance': -1.0,
      'local_contrast_enabled': true,
      'lc_detail': 0.35,
      'lc_clarity': 0.30,
      'grain_enabled': true,
      'gr_amount': 0.22,
      'vignette_enabled': true,
      'vg_amount': -0.45,
    },
  };

  /// 프리셋 맵을 현재 파라미터에 적용 (기하학 및 원본 촬영 WB 유지)
  static PipelineParams applyPresetMap(
    PipelineParams current,
    Map<String, dynamic> presetData,
  ) {
    final base = PipelineParams();
    base.wbAsShotTemp = current.wbAsShotTemp;
    base.wbAsShotTint = current.wbAsShotTint;
    if (!presetData.containsKey('wb_temperature')) {
      base.wbTemperature = current.wbAsShotTemp;
    }
    if (!presetData.containsKey('wb_tint')) {
      base.wbTint = current.wbAsShotTint;
    }
    base.rotate90 = current.rotate90;
    base.flipH = current.flipH;
    base.flipV = current.flipV;
    base.angle = current.angle;
    base.cropEnabled = current.cropEnabled;
    base.cropRect = List<double>.from(current.cropRect);

    final merged = base.toMap();
    presetData.forEach((k, v) {
      merged[k] = v;
    });
    return PipelineParams.fromMap(merged);
  }

  static Future<Directory> _getPresetsDir() async {
    final docDir = await getApplicationSupportDirectory();
    final dir = Directory('${docDir.path}/presets');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Map<String, Map<String, dynamic>>> loadUserPresets() async {
    final result = <String, Map<String, dynamic>>{};
    try {
      final dir = await _getPresetsDir();
      final files = dir.listSync().whereType<File>().where(
        (f) => f.path.toLowerCase().endsWith('.json'),
      );
      for (final file in files) {
        final filename = file.uri.pathSegments.last;
        if (filename == _deletedBuiltinsFileName) continue;
        final name = filename.substring(0, filename.length - 5);
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        result[name] = map;
      }
    } catch (_) {}
    return result;
  }

  /// 사용자가 삭제한 기본 내장 프리셋 이름 목록 로드
  static Future<Set<String>> loadDeletedBuiltinPresets() async {
    try {
      final dir = await _getPresetsDir();
      final file = File('${dir.path}/$_deletedBuiltinsFileName');
      if (await file.exists()) {
        final list = jsonDecode(await file.readAsString()) as List<dynamic>;
        return list.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  /// 기본 내장 프리셋 삭제 기록 저장
  static Future<void> markBuiltinPresetDeleted(String name) async {
    try {
      final deleted = await loadDeletedBuiltinPresets();
      deleted.add(name);
      final dir = await _getPresetsDir();
      final file = File('${dir.path}/$_deletedBuiltinsFileName');
      await file.writeAsString(jsonEncode(deleted.toList()));
    } catch (_) {}
  }

  static Future<void> saveUserPreset(String name, PipelineParams params) async {
    final dir = await _getPresetsDir();
    final safeName = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (safeName.isEmpty) return;
    final file = File('${dir.path}/$safeName.json');
    final map = params.toMap();
    map.remove('rotate_90');
    map.remove('flip_h');
    map.remove('flip_v');
    map.remove('angle');
    map.remove('crop_enabled');
    map.remove('crop_rect');
    map.remove('split_view_enabled');
    map.remove('split_position');
    map.remove('wb_as_shot_temp');
    map.remove('wb_as_shot_tint');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  /// 내장 프리셋이든 사용자 프리셋이든 모두 삭제 가능하도록 처리
  static Future<void> deletePreset(String name) async {
    if (builtinPresets.containsKey(name)) {
      await markBuiltinPresetDeleted(name);
    }
    final dir = await _getPresetsDir();
    final safeName = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    final file = File('${dir.path}/$safeName.json');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
