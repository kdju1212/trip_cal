# 검증 상태

## 로컬에서 확인한 사항

- 환경: Linux / JDK 21, Flutter·Dart·Android SDK 미설치. 사용자의 Windows PC에 직접 설치한 것이 아닙니다.
- Flutter 공식 stable Git 소스는 접근 가능하지만 SDK 바이너리 호스트 `storage.googleapis.com`는 환경 네트워크 정책에서 403으로 거절됩니다. 우회하지 않았습니다.
- pub.dev의 최신 안정 패키지 버전 및 요구 SDK를 조회했습니다. Flutter 3.47.9 공식 stable 템플릿을 확인해 Android/iOS 프로젝트를 구성했습니다.
- Dart 소스의 tree-sitter 구문 검사, JSON/XML/plist 구성, 키/비밀 파일 제외 상태를 검사합니다. 이는 Dart 정적 타입 분석이나 실행 검증을 대체하지 않습니다.

## 자동화된 검증

GitHub Actions는 Flutter 3.47.9 / JDK 17에서 `flutter pub get`, `flutter analyze`, `flutter test --reporter expanded`, debug/release-mode 테스트 APK 빌드를 실행합니다. 실제 실행 결과는 Actions 로그를 기준으로 판단해야 합니다.

최종 검증 커밋 `ce1acc8b77cf77571f46ee5fea09ecdad14c6212`: [Actions 실행 41839359570](https://github.com/kdju1212/trip_cal/actions/runs/41839359570) **성공**.

- `flutter analyze`: **No issues found** (오류·경고·스타일 권고 없음)
- `flutter test --reporter expanded`: **25개 모두 통과**
- Android debug APK 생성 성공
- release 모드 테스트 APK 3종 생성 성공: ARM 32비트 20.0MB, arm64 22.3MB, x86_64 23.9MB
- [arm64 APK artifact](https://github.com/kdju1212/trip_cal/actions/runs/41839359570/artifacts/13327139778), [전체 APK artifact](https://github.com/kdju1212/trip_cal/actions/runs/41839359570/artifacts/13328099755)

설치 파일 로컬 경로: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. 빌드 출처와 SHA-256은 `docs/BUILD_INFO.json`에 기록했습니다. 기본 APK와 ABI별 APK는 테스트용 debug 서명이며 광고는 테스트 ID입니다. Play 게시를 수행하지 않았습니다.

최종 로컬 소스는 이 실행에서 실제 분석·테스트·빌드한 `dart format` 출력과 동일한 파일을 반영했습니다. 검증 커밋과 토큰 동등성도 확인했습니다. 이후 커밋은 이 포맷 출력 및 검증 기록만 반영하며 CI 재실행을 생략합니다.


테스트 범위: 도메인 혼합 통화 예시(900,000원/남은 1,100,000원), 반올림/음수/0환율/통화 소수 자릿수/큰 금액, D-day/미정/지난 날짜, 통화 연결, DB CRUD/복제/격리/cascade/체크 상태/재연결/v1 마이그레이션, API 응답/캐시/오프라인/수동/중복 요청/저장된 경비 불변/재계산 중복 방지, 출발일 없는 여행 생성/국가 검색/작은 화면/다크모드/차트, 알림 설정 MethodChannel 계약.

## 아직 실기기 검증이 필요한 사항

- Android 알림의 실제 자정 갱신, 제조사 절전, 재부팅, 권한 거절과 탭 이동. 네이티브 코드는 AlarmManager 비정확 예약이며 강제 종료나 절전 시 정시 동작을 보장하지 않습니다.
- AdMob/UMP 실제 네트워크 통신과 동의 UI. 테스트 ID/동의 메시지 설정에 따라 배너가 나타나지 않을 수 있습니다. 동의 없이 실제 광고를 요청하도록 우회하지 않습니다.
- Frankfurter 실제 모바일 네트워크 조회, 외부 브라우저 연결, Android 접근성 리더 및 터치 동작.
- iOS 컴파일과 실행 (macOS/Xcode 필요). iOS D-day 알림은 구현 대상이 아니며 설정에서 사용할 수 없도록 표시합니다.

## 의도적으로 준비 중인 부분

- 앱 아이콘은 기본 템플릿. 출시 전 전용 아이콘 필요.
- 판매처 링크는 확인된 공식 사이트만 제공. 유심·용품 등 일부 항목은 구매 링크 준비 중. 가격·제휴·상품 품질은 보장하지 않습니다.
- 국가 콘텐츠는 준비 체크포인트 위주이며 비자 자격, 체류 가능 일수, 전압 등을 검증 없이 단정하지 않습니다.
- 개인정보 공개 URL, 운영자 정보, 실광고 ID, 서명 키, Play 등록정보와 게시 작업은 사용자 운영 단계에서 확정해야 합니다.
- DB 내보내기/복원과 앱 내 결제는 제공하지 않습니다.
