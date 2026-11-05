import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 필름스트립에 표시할 개별 사진 항목 데이터
class FilmstripItemData {
  final String filePath;
  final String fileName;
  final ui.Image? thumbnail;
  final int rating; // 0 ~ 5 별점

  const FilmstripItemData({
    required this.filePath,
    required this.fileName,
    required this.thumbnail,
    this.rating = 0,
  });
}

/// SemiDarktable의 하단 Filmstrip 바 1:1 이식
/// - 사진이 없을 때는 26px 헤더 바만 표시하여 뷰포트 공간을 침범하지 않음
/// - 접기/펼치기 토글, 사진 클릭 전환, 개별 사진 닫기(✕) 버튼 제공
/// - 우클릭(데스크톱) 및 길게 누르기(모바일)를 통한 현상 설정 복사/붙여넣기 및 별점(Rating: 0~5) 지정 지원
class FilmstripWidget extends StatelessWidget {
  final List<FilmstripItemData> items;
  final int currentIndex;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;
  final VoidCallback onAddFiles;
  final ValueChanged<int>? onCopySettings;
  final ValueChanged<int>? onPasteSettings;
  final bool hasCopiedSettings;
  final void Function(int index, int rating)? onSetRating;

  const FilmstripWidget({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onSelect,
    required this.onRemove,
    required this.onAddFiles,
    this.onCopySettings,
    this.onPasteSettings,
    this.hasCopiedSettings = false,
    this.onSetRating,
  });

  void _showContextMenu(BuildContext context, Offset globalPos, int idx) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(globalPos, globalPos),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<String>(
      context: context,
      position: position,
      color: const Color(0xFF292929),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFF444444)),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'copy',
          height: 36,
          child: Row(
            children: [
              Text('📋 ', style: TextStyle(fontSize: 13)),
              Text(
                '현상 설정 복사 (변형 제외)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          enabled: hasCopiedSettings,
          height: 36,
          child: Row(
            children: [
              const Text('📥 ', style: TextStyle(fontSize: 13)),
              Text(
                '현상 설정 붙여넣기',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hasCopiedSettings ? const Color(0xFFE8A838) : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        // 별점(Rating) 선택 메뉴
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(
            '⭐ 별점 지정 (XMP 연동):',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade400,
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'rating_dialog',
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int r = 1; r <= 5; r++)
                InkWell(
                  onTap: () {
                    Navigator.pop(context, 'rate_$r');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      '★$r',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: items[idx].rating >= r
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF888888),
                      ),
                    ),
                  ),
                ),
              InkWell(
                onTap: () {
                  Navigator.pop(context, 'rate_0');
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '☆0',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFAAAAAA),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'remove',
          height: 36,
          child: Row(
            children: [
              Text('✕ ', style: TextStyle(fontSize: 13, color: Color(0xFFFF6B6B))),
              Text(
                '이 사진 닫기',
                style: TextStyle(fontSize: 12, color: Color(0xFFFF6B6B)),
              ),
            ],
          ),
        ),
      ],
    );

    if (selected == 'copy') {
      onCopySettings?.call(idx);
    } else if (selected == 'paste') {
      onPasteSettings?.call(idx);
    } else if (selected == 'remove') {
      onRemove(idx);
    } else if (selected != null && selected.startsWith('rate_')) {
      final r = int.tryParse(selected.substring(5)) ?? 0;
      onSetRating?.call(idx, r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showStrip = !collapsed && items.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1D1D1D),
        border: Border(
          top: BorderSide(color: Color(0xFF333333), width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 필름스트립 상단 타이틀/접기 바
          InkWell(
            onTap: items.isEmpty ? onAddFiles : onToggleCollapse,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: const Color(0xFF252525),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 540;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          items.isEmpty
                              ? '🎞️ 필름스트립 (0장 로드됨 — 클릭하여 사진 추가)'
                              : (collapsed
                                  ? '▲ 필름스트립 펼치기 (${items.length}장 로드됨 — 별점/복사/붙여넣기)'
                                  : '▼ 필름스트립 접기 (${items.length}장 로드됨 — 별점/복사/붙여넣기)'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFBBBBBB),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isWide) ...[
                        const SizedBox(width: 8),
                        const Text(
                          '단축키 1~5 별점 지정 | 우클릭/길게누름: 설정 복사·별점 연동',
                          style:
                              TextStyle(fontSize: 10, color: Color(0xFF888888)),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
          if (showStrip)
            SizedBox(
              height: 88,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                itemCount: items.length,
                itemBuilder: (context, idx) {
                  final item = items[idx];
                  final isSelected = idx == currentIndex;
                  return GestureDetector(
                    onTap: () => onSelect(idx),
                    onSecondaryTapDown: (details) =>
                        _showContextMenu(context, details.globalPosition, idx),
                    onLongPressStart: (details) =>
                        _showContextMenu(context, details.globalPosition, idx),
                    child: Container(
                      width: 96,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFE8A838)
                              : const Color(0xFF3E3E3E),
                          width: isSelected ? 2.0 : 1.0,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3),
                                  ),
                                  child: item.thumbnail != null
                                      ? RawImage(
                                          image: item.thumbnail,
                                          fit: BoxFit.cover,
                                        )
                                      : const Center(
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              Container(
                                height: 18,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                color: isSelected
                                    ? const Color(0xFF3A2E18)
                                    : const Color(0xFF222222),
                                child: Center(
                                  child: Text(
                                    item.fileName,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: isSelected
                                          ? const Color(0xFFE8A838)
                                          : const Color(0xFFCCCCCC),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // 좌측 상단 별점 배지
                          if (item.rating > 0)
                            Positioned(
                              top: 2,
                              left: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xD9000000),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: const Color(0xFFFFD700),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '★',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFFFFD700),
                                      ),
                                    ),
                                    const SizedBox(width: 1.5),
                                    Text(
                                      '${item.rating}',
                                      style: const TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFFFD700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // 우측 상단 닫기(X) 버튼
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () => onRemove(idx),
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: const Color(0xB3000000),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Text(
                                    '✕',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
