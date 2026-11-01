import 'package:flutter/material.dart';
import 'double_tap_tracker.dart';

/// SemiDarktable의 SliderSpinRow 1:1 이식 위젯
/// - 라벨 + 직접 수치 입력/스핀 박스 + 슬라이더
/// - scale 지원 (예: scale = 0.01 이면 UI 슬라이더는 -100~+100을 표시하고 내부 파라미터는 -1.0~+1.0 저장)
/// - 슬라이더나 라벨 더블클릭 시 기본값(defaultVal)으로 즉시 복원
/// - 슬라이더 조작 시 상위 ModuleCard 자동 활성화(onAutoTurnOn) 지원
/// - 드래그 시작/종료 시 Undo 히스토리 1단계 저장(onChangeStart / onChangeEnd) 지원
class ControlSlider extends StatefulWidget {
  final String label;
  final double value; // 내부 실제 파라미터 값 (예: -1.0 ~ 1.0)
  final double min; // UI 표시 최소값 (예: -100.0)
  final double max; // UI 표시 최대값 (예: 100.0)
  final double defaultVal; // UI 표시 기본값 (예: 0.0)
  final double scale; // UI 값 -> 내부 값 변환 배율 (기본 1.0, 퍼센트형은 0.01)
  final int decimals;
  final String suffix;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;
  final VoidCallback? onAutoTurnOn;

  const ControlSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultVal,
    this.scale = 1.0,
    this.decimals = 2,
    this.suffix = '',
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onAutoTurnOn,
  });

  @override
  State<ControlSlider> createState() => _ControlSliderState();
}

class _ControlSliderState extends State<ControlSlider> {
  bool _isEditingText = false;
  late TextEditingController _textController;
  final FocusNode _textFocusNode = FocusNode();

  final DoubleTapTracker _doubleTap = DoubleTapTracker();
  bool _ignoreSliderChanges = false;

  double get _uiValue => (widget.value / widget.scale).clamp(widget.min, widget.max);

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: _uiValue.toStringAsFixed(widget.decimals),
    );
    _textFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    // 모바일 키보드 완료/내리기 또는 다른 영역 터치로 포커스가 해제될 때만 안전하게 수치 확정
    if (!_textFocusNode.hasFocus && _isEditingText) {
      _commitText(_textController.text);
    }
  }

  @override
  void didUpdateWidget(covariant ControlSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditingText && (oldWidget.value != widget.value || oldWidget.scale != widget.scale)) {
      _textController.text = _uiValue.toStringAsFixed(widget.decimals);
    }
  }

  @override
  void dispose() {
    _textFocusNode.removeListener(_onFocusChange);
    _textFocusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _resetToDefault() {
    widget.onChangeStart?.call();
    widget.onAutoTurnOn?.call();
    widget.onChanged(widget.defaultVal * widget.scale);
    widget.onChangeEnd?.call();
  }

  /// Slider 내부 제스처 인식기에 가로채이지 않도록 PointerDown 단계에서 직접 더블탭 감지
  /// (모바일에서 정확히 같은 위치를 누르기 어려우므로 허용 거리·시간을 넉넉하게 설정)
  void _handleSliderPointerDown(PointerDownEvent event) {
    if (_doubleTap.onPointerDown(event)) {
      // 두 번째 터치 동안 Slider가 값을 덮어쓰지 못하도록 막고 기본값으로 초기화
      _ignoreSliderChanges = true;
      _resetToDefault();
    }
  }

  void _handleSliderPointerUp(PointerUpEvent event) {
    _doubleTap.onPointerUp(event);
    _releaseSliderGuard();
  }

  void _handleSliderPointerCancel(PointerCancelEvent event) {
    _doubleTap.onPointerCancel(event);
    _releaseSliderGuard();
  }

  /// 손을 뗀 직후 Slider가 뒤늦게 보내는 변경 이벤트까지 막은 뒤 가드 해제
  void _releaseSliderGuard() {
    if (!_ignoreSliderChanges) return;
    Future.delayed(const Duration(milliseconds: 150), () {
      _ignoreSliderChanges = false;
    });
  }

  void _commitText(String raw) {
    setState(() => _isEditingText = false);
    final parsed = double.tryParse(raw.trim());
    if (parsed != null) {
      final clampedUi = parsed.clamp(widget.min, widget.max);
      widget.onChangeStart?.call();
      widget.onAutoTurnOn?.call();
      widget.onChanged(clampedUi * widget.scale);
      widget.onChangeEnd?.call();
    } else {
      _textController.text = _uiValue.toStringAsFixed(widget.decimals);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clampedVal = _uiValue;
    final isModified = (clampedVal - widget.defaultVal).abs() > 1e-4;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: GestureDetector(
                  onDoubleTap: _resetToDefault,
                  child: Tooltip(
                    message: '더블클릭하여 기본값(${widget.defaultVal.toStringAsFixed(widget.decimals)})으로 초기화',
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isModified
                            ? const Color(0xFFE0E0E0)
                            : const Color(0xFFB0B0B0),
                        fontWeight:
                            isModified ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _isEditingText
                  ? SizedBox(
                      width: 68,
                      height: 24,
                      child: TextField(
                        controller: _textController,
                        focusNode: _textFocusNode,
                        textInputAction: TextInputAction.done,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1A1A1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(3),
                            borderSide: const BorderSide(
                              color: Color(0xFFE8A838),
                            ),
                          ),
                        ),
                        onSubmitted: _commitText,
                      ),
                    )
                  : GestureDetector(
                      onTap: () {
                        setState(() {
                          _isEditingText = true;
                          _textController.text =
                              clampedVal.toStringAsFixed(widget.decimals);
                          _textController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _textController.text.length,
                          );
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _isEditingText) {
                            _textFocusNode.requestFocus();
                          }
                        });
                      },
                      onDoubleTap: _resetToDefault,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: isModified
                                ? const Color(0xFF554422)
                                : const Color(0xFF333333),
                          ),
                        ),
                        child: Text(
                          '${clampedVal.toStringAsFixed(widget.decimals)}${widget.suffix}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: isModified
                                ? const Color(0xFFE8A838)
                                : const Color(0xFFAAAAAA),
                          ),
                        ),
                      ),
                    ),
            ],
          ),
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleSliderPointerDown,
            onPointerMove: _doubleTap.onPointerMove,
            onPointerUp: _handleSliderPointerUp,
            onPointerCancel: _handleSliderPointerCancel,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.0,
                activeTrackColor: const Color(0xFFE8A838),
                inactiveTrackColor: const Color(0xFF1A1A1A),
                thumbColor: isModified
                    ? const Color(0xFFE8A838)
                    : const Color(0xFF999999),
                overlayColor: const Color(0x29E8A838),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6.0,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 11.0,
                ),
              ),
              child: Slider(
                value: clampedVal,
                min: widget.min,
                max: widget.max,
                onChangeStart: (_) {
                  if (_ignoreSliderChanges) return;
                  widget.onChangeStart?.call();
                  widget.onAutoTurnOn?.call();
                },
                onChanged: (uiVal) {
                  if (_ignoreSliderChanges) return;
                  widget.onChanged(uiVal * widget.scale);
                },
                onChangeEnd: (_) {
                  if (_ignoreSliderChanges) return;
                  widget.onChangeEnd?.call();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
