# PhotonRaw (포톤 로우)
> **iOS, macOS, Android, Windows, Web** 모든 플랫폼을 지원하는 고성능 32-bit Float RAW 사진 현상 스튜디오

기존 **SemiDarktable**의 32비트 무손실 연산 파이프라인, 정밀 노출 제어, 시그모이드(Sigmoid) 톤 매핑 및 특화 프리셋 시스템을 완벽하게 계승하여 Flutter 크로스 플랫폼으로 새로 제작된 프로젝트입니다.

---

## 🌟 주요 기능
1. **완전한 크로스 플랫폼 지원**:
   - iPhone (iOS), Mac (macOS), Android 폰/태블릿, Windows PC, 웹(Web)까지 동일한 단일 코드베이스로 작동
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

## 🚀 실행 및 빌드 방법

### 1. Windows 데스크톱에서 바로 실행
- 폴더 내 `run_photonraw.bat`을 더블 클릭하거나 명령 프롬프트에서:
```bash
flutter run -d windows
```

### 2. 안드로이드 (Android) 빌드 및 실행
```bash
flutter run -d android
flutter build apk --release
```

### 3. 아이폰 (iOS) 및 맥 (macOS) 빌드
> iOS/macOS 빌드는 Apple 정책상 macOS 환경(Xcode 설치)에서 실행해야 합니다.
```bash
# macOS 데스크톱 실행
flutter run -d macos

# iPhone / iPad 실행
flutter run -d ios
flutter build ipa
```

### 4. 웹 브라우저에서 실행
```bash
flutter run -d chrome
```
