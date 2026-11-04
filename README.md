# 여행 준비 도우미

로그인·자체 서버 없이 여행 출발 전 예상 경비와 준비물을 관리하는 한국어 Flutter 앱입니다. Android 우선, iOS 프로젝트 포함. 실지출 가계부가 아닙니다.

## 실행 (Windows)

Flutter **3.47.9 stable**, Android Studio/SDK, JDK 17 이상을 설치하고:

```powershell
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
flutter run
```

기존 `android`/`ios` 파일을 다시 생성할 필요가 없습니다. Android 최소 버전은 API 24입니다. iOS 빌드는 macOS/Xcode가 필요하며 현재 iOS 실행은 검증하지 않았습니다.

## 구현 범위

- 여행 생성·수정·삭제 확인·복제, 출발일 선택, 국가 검색 (28개 국가/지역)
- 경비별 KRW/현지 통화, 기존 국가의 통화 보존, 경비 CRUD·사용자 카테고리
- Decimal/BigInt 환산, 정수 원화 반올림, 0원 예산·초과 처리
- Frankfurter v2 참고 환율, 기준 날짜·출처·직접 입력·SQLite 캐시·10초 타임아웃·동시 요청 병합
- 환율 조회와 경비 변경 분리, 재계산 미리보기·확인·원래 금액으로 재계산
- 카테고리 합계·도넛/막대 차트·예산 진행률
- 국가별 기본 준비물·체크/추가/수정/삭제·자동 저장, 구매 필요 항목 저장
- 일본·미국·태국·베트남 공식 안내 링크 포함 정적 콘텐츠, 그 외 공통 팁
- 검증된 판매처 홈페이지 링크 (일부 항목만), 제휴 없음
- Android D-day ongoing notification, 권한 요청·날짜 갱신·자동 여행 선택·탭 이동·재부팅 복원
- Material 3 한국어 UI, 라이트/다크/기기 설정, 작은 화면 스크롤
- AdMob 테스트 배너와 UMP 동의 흐름. 동의 확인 불가/광고 실패 시 배너 없이 작동
- SQLite v2 스키마, v1 마이그레이션, 외래 키 cascade 및 트랜잭션

## 검증 및 APK

```powershell
flutter analyze
flutter test --reporter expanded
flutter build apk --debug
flutter build apk --release --no-shrink
```

생성 경로:

- `build/app/outputs/flutter-apk/app-debug.apk`
- `build/app/outputs/flutter-apk/app-release.apk` (로컬 기본 릴리스 빌드)
- CI는 `--split-per-abi`로 `app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk`를 생성합니다.

키가 없으면 release 모드도 **테스트용 debug 서명**입니다. Play 업로드용이 아닙니다.

GitHub Actions의 **Flutter checks and Android APK**가 위 정적 분석·테스트·두 APK 빌드를 실행합니다. 성공한 실행의 `trip-cal-test-apks` artifact에서 설치 파일을 받을 수 있습니다. 일반적인 최근 Android 휴대폰용 arm64 파일은 `trip-cal-arm64-apk` artifact로도 제공합니다. 빌드 실패 시 APK가 없으므로 실행 결과를 먼저 확인하세요.

## 파일 구성

`lib/domain.dart`: 국가·통화·정밀 계산 / `storage.dart`: SQLite 및 마이그레이션 / `controller.dart`: 상태·설정 갱신 / `services/`: 환율·알림·광고 / `screens/`: 8개 화면 / `widgets/`: 차트·배너·공통 입력 / `assets/tips/`: 국가별 JSON / `android/`: 네이티브 알림·Gradle / `ios/`: Xcode 프로젝트 / `test/`: 도메인·DB·API·위젯·알림 채널 테스트.

세부 검증 상태와 제한은 [docs/VERIFICATION.md](docs/VERIFICATION.md), 서명 AAB·광고·스토어 준비는 [docs/RELEASE.md](docs/RELEASE.md), 개인정보 초안은 [docs/PRIVACY.md](docs/PRIVACY.md)를 확인하세요.

## 주요 패키지

`sqflite` 2.4.5, `decimal` 3.2.6, `fl_chart` 1.3.0, `http` 1.6.0, `url_launcher` 6.3.3, `google_mobile_ads` 9.2.0, `path` 1.9.1, Flutter localization/intl. 상태는 Flutter ChangeNotifier로 관리하고 Android 알림은 Kotlin MethodChannel로 구현했습니다. 테스트는 `flutter_test`, `sqflite_common_ffi` 2.4.5를 사용합니다. 실제 확정 버전은 `pubspec.lock`에 저장했습니다.

릴리스 APK의 코드 축소는 Android WorkManager 초기화에 필요한 생성자가 제거되는 문제를 피하기 위해 비활성화되어 있습니다. APK 또는 AAB를 만들 때 `--no-shrink`를 유지하세요.
