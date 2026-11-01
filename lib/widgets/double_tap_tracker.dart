import 'package:flutter/gestures.dart';

/// 모바일/데스크톱 공용 더블탭 추적기.
///
/// - 모바일에서 손가락 터치 시 미세한 흔들림(이동)이 있어도 안전하게 더블탭 감지
/// - 두 번의 탭(PointerDown) 간격이 [maxInterval] 이내이고, 거리 오차가 [maxDistance] 이내이면 더블탭 인정
/// - 단, 1초 이상 길게 누르고 있었던 롱 드래그는 더블탭으로 오인하지 않음
class DoubleTapTracker {
  final Duration maxInterval;
  final double maxDistance;

  DoubleTapTracker({
    this.maxInterval = const Duration(milliseconds: 500),
    this.maxDistance = 80.0,
  });

  DateTime? _firstDownTime;
  Offset? _firstDownPos;
  int? _firstPointer;
  bool _isLongPress = false;

  /// 포인터가 눌렸을 때 호출. 더블탭으로 판정되면 true 반환
  bool onPointerDown(PointerDownEvent e) {
    // 마우스는 주 버튼(좌클릭)만 대상
    if (e.kind == PointerDeviceKind.mouse && (e.buttons & kPrimaryButton) == 0) {
      return false;
    }
    final now = DateTime.now();

    // 이전 터치가 있고 유효 시간/거리 이내인 경우 -> 더블탭 인정!
    if (_firstDownTime != null &&
        _firstDownPos != null &&
        !_isLongPress &&
        now.difference(_firstDownTime!) < maxInterval &&
        (e.localPosition - _firstDownPos!).distance < maxDistance) {
      _firstDownTime = null;
      _firstDownPos = null;
      _firstPointer = null;
      _isLongPress = false;
      return true;
    }

    // 첫 번째 터치 기록
    _firstDownTime = now;
    _firstDownPos = e.localPosition;
    _firstPointer = e.pointer;
    _isLongPress = false;
    return false;
  }

  void onPointerMove(PointerMoveEvent e) {
    // 이동량이 너무 크면(120px 초과 화면 횡단 드래그) 더블탭 후보 취소
    if (e.pointer == _firstPointer && _firstDownPos != null) {
      if ((e.localPosition - _firstDownPos!).distance > 120.0) {
        _isLongPress = true;
      }
    }
  }

  void onPointerUp(PointerUpEvent e) {
    if (e.pointer == _firstPointer) {
      // 550ms 이상 길게 누르고 있었던 드래그는 더블탭 대상에서 제외
      if (_firstDownTime != null &&
          DateTime.now().difference(_firstDownTime!) > const Duration(milliseconds: 550)) {
        _firstDownTime = null;
        _firstDownPos = null;
      }
    }
  }

  void onPointerCancel(PointerCancelEvent e) {
    if (e.pointer == _firstPointer) {
      _firstDownTime = null;
      _firstDownPos = null;
      _firstPointer = null;
    }
  }
}

