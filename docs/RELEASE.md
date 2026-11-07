# Android 출시 준비

## 서명과 AAB (Windows PowerShell)

Google Play에 업로드하거나 유료 서비스에 가입하지 않았습니다. 릴리스 전에 앱 ID `com.tripcal.app`의 고유성과 운영자 정보를 확정하세요.

1. 안전한 로컬 위치에서 업로드 키를 만듭니다. 암호를 명령 인자나 Git에 기록하지 마세요.

```powershell
keytool -genkeypair -v -keystore C:\secure\trip-cal-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. `android/key.properties.example`을 `android/key.properties`로 복사해 로컬에서만 값을 입력합니다. 키·암호 파일은 gitignore 대상이며 커밋하지 않습니다.
3. `flutter test`와 정적 분석을 통과한 뒤:

```powershell
flutter build appbundle --release --no-shrink
```

결과: `build/app/outputs/bundle/release/app-release.aab`. 키 설정이 없으면 테스트용 debug 서명이므로 업로드하면 안 됩니다. 업로드 전 `jarsigner -verify -verbose -certs` 등으로 실제 서명을 확인하세요. Play App Signing 사용과 키 백업/보관 책임을 정하세요.

## Play 제출 전 남은 작업

- 운영자명/개인정보 문의처, 공개 개인정보처리방침 HTTPS URL을 확정하고 Play 등록정보 및 앱 안내를 갱신합니다.
- 대상 연령, 콘텐츠 등급, 앱 액세스(로그인 없음), 타깃 API와 SDK 정책을 제출 시점에 확인합니다.
- 물리 Android 기기(API 24, 26, 33, 34 이상 포함)에서 알림 권한 거절/허용, 앱 종료·재부팅·자정·시간대 변경·절전·여행 삭제와 만료를 테스트합니다. Ongoing 알림의 해제 불가능성을 보장하지 않습니다. 강제 종료 상태의 백그라운드 동작은 보장하지 않습니다.
- 오프라인·0예산·큰 금액·큰 글씨·화면 회전·한국어·다크모드를 검증합니다.
- 판매처/국가 콘텐츠와 공식 출처의 유효성을 다시 확인합니다. 제휴 링크를 추가하면 데이터와 고지 문구를 함께 수정합니다.
- 앱 아이콘과 스토어 스크린샷을 제작합니다. 현재 아이콘은 Flutter 템플릿 기본 아이콘으로 출시 전 교체해야 합니다.
- 내부/비공개 테스트 및 계정별 Play 테스트 요구사항을 완료하고 사용자가 게시를 승인한 뒤 제출합니다.

릴리스 코드 축소는 WorkManager 데이터베이스 생성자가 제거되어 앱이 시작할 때 종료되는 문제를 방지하기 위해 비활성화했습니다. 최적화 설정을 변경하는 경우 반드시 실제 릴리스 APK의 시작을 Android 기기에서 다시 검증하세요.
