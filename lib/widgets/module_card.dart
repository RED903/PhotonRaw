import 'package:flutter/material.dart';

/// SemiDarktable의 ModuleCard 1:1 이식 위젯
/// - 전원 토글 버튼 (⏻, 활성화 시 초록색 강조)
/// - 아코디언 접기/펼치기 (▼ / ▶) — 스크롤을 내렸다 올려도 열림/닫힘 상태가 절대 초기화되지 않도록 KeepAlive 및 상위 상태 연동 지원
/// - 모듈 개별 초기화 버튼 (↺)
class ModuleCard extends StatefulWidget {
  final String title;
  final String category;
  final bool enabled;
  final bool initiallyExpanded;
  final bool? expanded;
  final ValueChanged<bool>? onExpansionChanged;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onReset;
  final List<Widget> children;

  const ModuleCard({
    super.key,
    required this.title,
    required this.category,
    required this.enabled,
    this.initiallyExpanded = false,
    this.expanded,
    this.onExpansionChanged,
    required this.onToggleEnabled,
    required this.onReset,
    required this.children,
  });

  @override
  State<ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<ModuleCard>
    with AutomaticKeepAliveClientMixin {
  late bool _internalExpanded;

  @override
  bool get wantKeepAlive => true;

  bool get _isExpanded => widget.expanded ?? _internalExpanded;

  @override
  void initState() {
    super.initState();
    _internalExpanded = widget.expanded ?? widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant ModuleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != null && widget.expanded != _internalExpanded) {
      _internalExpanded = widget.expanded!;
    }
  }

  void _toggleExpand() {
    final next = !_isExpanded;
    setState(() {
      _internalExpanded = next;
    });
    widget.onExpansionChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final expanded = _isExpanded;
    final borderColor = widget.enabled
        ? const Color(0xFF4A6B4A)
        : const Color(0xFF363636);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더 영역
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: widget.enabled
                  ? const Color(0xFF2F382F)
                  : const Color(0xFF2B2B2B),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(4),
                bottom: Radius.circular(expanded ? 0 : 4),
              ),
            ),
            child: Row(
              children: [
                // 전원 버튼 (⏻)
                Tooltip(
                  message: widget.enabled ? '모듈 끄기 (바이패스)' : '모듈 켜기',
                  child: InkWell(
                    onTap: () => widget.onToggleEnabled(!widget.enabled),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 24,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.enabled
                            ? const Color(0xFF2E4D2E)
                            : const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: widget.enabled
                              ? const Color(0xFF66CC66)
                              : const Color(0xFF444444),
                        ),
                      ),
                      child: Icon(
                        Icons.power_settings_new,
                        size: 14,
                        color: widget.enabled
                            ? const Color(0xFF66CC66)
                            : const Color(0xFF666666),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 모듈 제목 + 아코디언 토글
                Expanded(
                  child: InkWell(
                    onTap: _toggleExpand,
                    child: Row(
                      children: [
                        Text(
                          expanded ? '▼ ' : '▶ ',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF999999),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: widget.enabled
                                  ? const Color(0xFFEAEAEA)
                                  : const Color(0xFF9A9A9A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 모듈 초기화 버튼 (↺)
                Tooltip(
                  message: '이 모듈의 파라미터를 기본값으로 초기화',
                  child: InkWell(
                    onTap: widget.onReset,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 24,
                      height: 22,
                      alignment: Alignment.center,
                      child: const Text(
                        '↺',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFAAAAAA),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 본문 영역
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}
