import 'package:flutter/gestures.dart';

/// 모바일/데스크톱 공용 더블탭 추적기.
///
/// - 첫 번째 터치는 '탭'(이동량이 작고 짧게 눌렀다 뗌)이어야 하며, 드래그 조작 직후의 터치는 더블탭으로 오인하지 않음
/// - 두 번째 터치는 [maxInterval] 이내, 첫 탭 위치에서 [maxDistance] 이내면 더블탭으로 인정
///   (손가락으로 정확히 같은 위치를 두 번 누르기 어려운 모바일을 위해 허용 거리를 넉넉하게 설정)
class DoubleTapTracker {
  final Duration maxInterval;
  final double maxDistance;
  final double tapSlop;
  final Duration maxTapDuration;

  DoubleTapTracker({
    this.maxInterval = const Duration(milliseconds: 550),
    this.maxDistance = 90.0,
    this.tapSlop = 16.0,
    this.maxTapDuration = const Duration(milliseconds: 400),
  });

  DateTime? _downTime;
  Offset? _downPos;
  bool _moved = false;
  int? _activePointer;

  DateTime? _lastTapUpTime;
  Offset? _lastTapUpPos;

  /// 포인터가 눌렸을 때 호출. 더블탭으로 판정되면 true 반환
  bool onPointerDown(PointerDownEvent e) {
    // 마우스는 주 버튼(좌클릭)만 대상
    if (e.kind == PointerDeviceKind.mouse && (e.buttons & kPrimaryButton) == 0) {
      return false;
    }
    final now = DateTime.now();
    _activePointer = e.pointer;
    _downTime = now;
    _downPos = e.localPosition;
    _moved = false;

    if (_lastTapUpTime != null &&
        _lastTapUpPos != null &&
        now.difference(_lastTapUpTime!) < maxInterval &&
        (e.localPosition - _lastTapUpPos!).distance < maxDistance) {
      _lastTapUpTime = null;
      _lastTapUpPos = null;
      // 이번 터치는 더블탭의 두 번째 터치이므로 추가 탭으로 쓰지 않음
      _downTime = null;
      return true;
    }
    return false;
  }

  void onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _activePointer || _downPos == null) return;
    if ((e.localPosition - _downPos!).distance > tapSlop) {
      _moved = true;
    }
  }

  void onPointerUp(PointerUpEvent e) {
    if (e.pointer != _activePointer) return;
    final down = _downTime;
    if (down != null &&
        !_moved &&
        DateTime.now().difference(down) < maxTapDuration) {
      _lastTapUpTime = DateTime.now();
      _lastTapUpPos = e.localPosition;
    } else {
      _lastTapUpTime = null;
      _lastTapUpPos = null;
    }
    _activePointer = null;
    _downTime = null;
  }

  void onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    _downTime = null;
    _lastTapUpTime = null;
    _lastTapUpPos = null;
  }
}
