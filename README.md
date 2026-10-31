# PhotonRaw (포톤 로우)
> **Android, iOS, macOS, Windows** 4대 플랫폼을 지원하는 순수 네이티브 32-bit Float RAW 사진 현상 스튜디오

기존 **SemiDarktable**의 32비트 무손실 연산 파이프라인, 정밀 노출 제어, 시그모이드(Sigmoid) 톤 매핑 및 특화 프리셋 시스템을 완벽하게 계승하여 제작된 고성능 순수 네이티브 앱입니다. 대용량 RAW 파일 처리를 위해 웹(브라우저) 샌드박스를 배제하고 OS 직접 메모리 할당 기반 네이티브 엔진으로 동작합니다.

---

## 🌟 지원 플랫폼 및 네이티브 설치 파일
- 📱 **Android**: `PhotonRaw-Android.apk` (안드로이드 폰/태블릿)
- 🍏 **iOS**: `PhotonRaw-iOS.ipa` (AltStore / Sideloadly 등을 통한 순정 아이폰 설치)
- 🖥️ **Windows**: `PhotonRaw-Windows-x64.zip` (윈도우 64-bit 실행 파일)
- 🍎 **macOS**: `PhotonRaw-macOS.zip` (Mac 데스크톱 앱)

---

## 🌟 주요 기능
1. **OS 직접 메모리 할당 (순수 네이티브)**:
   - 4500만 화소 이상의 고해상도 RAW 파일도 브라우저 메모리 제한 없이 안정적으로 처리
2. **32-bit Float 정밀 파이프라인**:
   - 노출(Exposure EV, Contrast, Black Level)
   - 화이트 밸런스(색온도 Temperature, 틴트 Tint)
   - 시그모이드 톤 매핑(Sigmoid Contrast, Skew) - Darktable 특유의 영화 같은 톤 표현
   - 디테일 복원(하이라이트 복원, 섀도우 밝기 복원)
   - 생동감(Vibrance) & 채도(Saturation)
3. **실시간 RGB & Luma 히스토그램 스코프**:
   - 256단계 정밀 채널 분포 및 피크 실시간 시각화
4. **Before / After 분할 비교 뷰포트**:
   - 원본과 보정본을 실시간으로 비교 가능
5. **SemiDarktable 100% 호환 프리셋 5종 기본 내장**:
   - 🌲 **Vivid Landscape** (풍경 비비드)
   - 🌸 **Warm Portrait** (인물 웜톤)
   - 🎞️ **Modern Film** (필름 룩)
   - 🎬 **Cinematic Moody** (시네마틱 무디)
   - 🖤 **B&W Fine Art** (흑백 파인아트)
   - 🔄 **00 Default** (기본값 초기화)
6. **다양한 포맷 입출력**:
   - 지원 입력: 카메라 RAW (DNG, CR2, NEF, ARW, RAF, RW2, ORF), TIFF, PNG, JPEG, WebP
   - 지원 내보내기: JPEG (고품질), PNG (무손실), 16-bit Master TIFF

---

## 🚀 GitHub 자동 빌드 및 다운로드 방법
GitHub에 태그를 푸시하면 GitHub 클라우드 머신이 자동으로 4대 플랫폼 바이너리를 빌드하여 **Releases** 탭에 올려줍니다.

```bash
git add .
git commit -m "release: v1.0.0"
git tag v1.0.0
git push origin main --tags
```
빌드 완료 후 GitHub 저장소의 **[Releases]**에서 APK, IPA, ZIP 파일을 다운로드하여 각 기기에서 바로 설치할 수 있습니다.
