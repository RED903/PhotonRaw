import 'package:flutter/material.dart';
import '../services/raw_decoder.dart';

/// 하단 큐 & 필름스트립 (다중 파일 탐색기)
class FilmstripWidget extends StatelessWidget {
  final List<RawImageResult> images;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final bool isExpanded;
  final VoidCallback onToggle;

  const FilmstripWidget({
    super.key,
    required this.images,
    required this.currentIndex,
    required this.onSelect,
    required this.onClose,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(top: BorderSide(color: Color(0xFF282828))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 접기/펼치기 헤더 바
          InkWell(
            onTap: onToggle,
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: const Color(0xFF181818),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    size: 18,
                    color: const Color(0xFFDCA353),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '🎞️ 큐 (${images.length}장)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDCA353),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '탐색기에서 사진/ARW를 끌어다 놓아 추가할 수 있습니다',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          // 썸네일 스크롤 리스트
          if (isExpanded)
            SizedBox(
              height: 85,
              child: images.isEmpty
                  ? const Center(
                      child: Text(
                        '열린 사진이 없습니다. [사진 열기] 또는 드래그 앤 드롭으로 추가하세요.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      itemCount: images.length,
                      itemBuilder: (context, idx) {
                        final item = images[idx];
                        final isSelected = idx == currentIndex;

                        return GestureDetector(
                          onTap: () => onSelect(idx),
                          child: Container(
                            width: 105,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF262626) : const Color(0xFF1B1B1B),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected ? const Color(0xFFDCA353) : const Color(0xFF333333),
                                width: isSelected ? 2.0 : 1.0,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // 썸네일 프리뷰
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                        child: Image.memory(
                                          item.previewImage.getBytes(),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 24),
                                        ),
                                      ),
                                    ),
                                    // 파일명
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Text(
                                        item.filename,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isSelected ? Colors.white : Colors.grey[400],
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // 삭제 X 버튼
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () => onClose(idx),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, size: 12, color: Colors.white70),
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
