import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 필름스트립에 표시할 개별 사진 항목 데이터
class FilmstripItemData {
  final String filePath;
  final String fileName;
  final ui.Image? thumbnail;

  const FilmstripItemData({
    required this.filePath,
    required this.fileName,
    required this.thumbnail,
  });
}

/// SemiDarktable의 하단 Filmstrip 바 1:1 이식
/// - Image.memory에 미인코딩 바이트를 넣어 멈추던 버그를 완전히 제거하고 GPU 텍스처(RawImage)로 즉시 렌더링
/// - 접기/펼치기 토글, 사진 클릭 전환, 개별 사진 닫기(✕) 버튼 제공
class FilmstripWidget extends StatelessWidget {
  final List<FilmstripItemData> items;
  final int currentIndex;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;
  final VoidCallback onAddFiles;

  const FilmstripWidget({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onSelect,
    required this.onRemove,
    required this.onAddFiles,
  });

  @override
  Widget build(BuildContext context) {
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
            onTap: onToggleCollapse,
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: const Color(0xFF252525),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    collapsed
                        ? '▲ 필름스트립 펼치기 (${items.length}장 로드됨)'
                        : '▼ 필름스트립 접기 (${items.length}장 로드됨)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFBBBBBB),
                    ),
                  ),
                  const Text(
                    '단축키: ← / → 사진 전환',
                    style: TextStyle(fontSize: 10, color: Color(0xFF777777)),
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            SizedBox(
              height: 92,
              child: items.isEmpty
                  ? Center(
                      child: TextButton.icon(
                        onPressed: onAddFiles,
                        icon: const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 16,
                          color: Color(0xFFE8A838),
                        ),
                        label: const Text(
                          '사진 열기 또는 화면에 이미지/RAW 파일을 드래그 앤 드롭하세요',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF999999),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius:
                                            const BorderRadius.vertical(
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
                                                  child:
                                                      CircularProgressIndicator(
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
                                      alignment: Alignment.center,
                                      color: isSelected
                                          ? const Color(0xFF3A2E18)
                                          : const Color(0xFF222222),
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
                                  ],
                                ),
                                // 개별 닫기(✕) 버튼
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: InkWell(
                                    onTap: () => onRemove(idx),
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xB3000000),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
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
