# 검증 상태

## 로컬에서 확인한 사항

- 환경: Linux / JDK 21, Flutter·Dart·Android SDK 미설치. 사용자의 Windows PC에 직접 설치한 것이 아닙니다.
- Flutter 공식 stable Git 소스는 접근 가능하지만 SDK 바이너리 호스트 `storage.googleapis.com`는 환경 네트워크 정책에서 403으로 거절됩니다. 우회하지 않았습니다.
- pub.dev의 최신 안정 패키지 버전 및 요구 SDK를 조회했습니다. Flutter 3.47.9 공식 stable 템플릿을 확인해 Android/iOS 프로젝트를 구성했습니다.
- Dart 소스의 tree-sitter 구문 검사, JSON/XML/plist 구성, 키/비밀 파일 제외 상태를 검사합니다. 이는 Dart 정적 타입 분석이나 실행 검증을 대체하지 않습니다.

## 자동화된 검증

GitHub Actions는 Flutter 3.47.9 / JDK 17에서 `flutter pub get`, `flutter analyze`, `flutter test --reporter expanded`, debug/release-mode 테스트 APK 빌드를 실행합니다. 실제 실행 결과는 Actions 로그를 기준으로 판단해야 합니다.

Android 릴리스 APK 시작 오류를 수정했습니다. 기존 `ce1acc8` 릴리스는 R8 코드 축소 과정에서 `androidx.work.impl.WorkDatabase_Impl`의 기본 생성자가 제거되어 시작 시 종료됐습니다. Android 15 가상 기기에서 기존 APK 오류를 재현했습니다.

수정 커밋 `af77192`는 릴리스 코드 축소를 비활성화합니다. [빌드 및 실행 검사](https://github.com/kdju1212/trip_cal/actions/runs/41843432137)에서 정적 분석과 자동 테스트 25개, Android APK 빌드, Android 15 가상 기기의 릴리스 앱 시작을 확인했습니다. 수정된 arm64 APK에 필요한 생성자가 포함된 것도 확인했습니다. Android 17 가상 기기 검사는 테스트 환경의 저장 공간 및 패키지 관리자 문제로 결론을 내리지 못했습니다. 사용자는 수정 APK가 Android 17을 사용하는 갤럭시 S26에서 열린다고 확인했습니다.

검증한 arm64 APK 로컬 경로는 `build/app/outputs/flutter-apk/trip-cal-fixed-arm64.apk`입니다. APK 해시와 출처는 `docs/BUILD_INFO.json`에 있습니다. debug 서명을 사용합니다.


테스트 범위: 도메인 혼합 통화 예시(900,000원/남은 1,100,000원), 반올림/음수/0환율/통화 소수 자릿수/큰 금액, D-day/미정/지난 날짜, 통화 연결, DB CRUD/복제/격리/cascade/체크 상태/재연결/v1 마이그레이션, API 응답/캐시/오프라인/수동/중복 요청/저장된 경비 불변/재계산 중복 방지, 출발일 없는 여행 생성/국가 검색/작은 화면/다크모드/차트, 알림 설정 MethodChannel 계약.

## 여러 경비 일괄 입력 변경

[검증 실행 42018215637](https://github.com/kdju1212/trip_cal/actions/runs/42018215637)에서 정적 분석 문제 0건, 자동 테스트 29개 통과 및 일반·별도 테스트 APK 빌드가 성공했습니다. 항목과 금액의 한 줄 배치, 줄별 외화 선택 및 변경 취소, 같은 항목의 복수 입력과 전체 저장, 오류 시 전체 취소 테스트가 포함됩니다. 별도 테스트 APK의 앱 ID, 실행 액티비티, 알림 리시버 및 WorkManager 생성자를 확인했습니다. Android 15 가상 기기에서 기본 앱과 별도 테스트 앱을 각각 설치하고 시작 화면이 표시되는 것도 확인했습니다.

`com.tripcal.app.preview` 테스트 앱은 기존 앱과 별도 설치되며 앱 데이터가 자동으로 공유되거나 복사되지 않습니다. 기존 앱의 데이터에는 영향을 주지 않습니다.

## 아직 실기기 검증이 필요한 사항

- Android 알림의 실제 자정 갱신, 제조사 절전, 재부팅, 권한 거절과 탭 이동. 네이티브 코드는 AlarmManager 비정확 예약이며 강제 종료나 절전 시 정시 동작을 보장하지 않습니다.
- Frankfurter 실제 모바일 네트워크 조회, 외부 브라우저 연결, Android 접근성 리더 및 터치 동작.
- iOS 컴파일과 실행 (macOS/Xcode 필요). iOS D-day 알림은 구현 대상이 아니며 설정에서 사용할 수 없도록 표시합니다.

## 의도적으로 준비 중인 부분

- 앱 아이콘은 기본 템플릿. 출시 전 전용 아이콘 필요.
- 판매처 링크는 확인된 공식 사이트만 제공. 유심·용품 등 일부 항목은 구매 링크 준비 중. 가격·제휴·상품 품질은 보장하지 않습니다.
- 국가 콘텐츠는 준비 체크포인트 위주이며 비자 자격, 체류 가능 일수, 전압 등을 검증 없이 단정하지 않습니다.
- 개인정보 공개 URL, 운영자 정보, 서명 키, Play 등록정보와 게시 작업은 사용자 운영 단계에서 확정해야 합니다.
- DB 내보내기/복원과 앱 내 결제는 제공하지 않습니다.
