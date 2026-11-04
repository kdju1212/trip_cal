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

## 실제 AdMob 광고

현재 Android/iOS App ID와 배너 ID는 Google 공식 테스트 ID입니다. 테스트 광고도 동의 흐름이 광고 요청을 허용할 때만 표시됩니다. UMP 테스트 앱 구성에 따라 동의 정보 요청이 실패해 배너가 나타나지 않을 수 있습니다.

- AdMob에서 본인 앱과 **배너** 광고 단위를 생성합니다. 전면·보상형 광고는 코드에 없습니다.
- AdMob Privacy & messaging에서 필요한 지역별 동의 메시지를 구성하고 실제 기기·지역에서 검증합니다. 앱 내 광고 개인정보 설정 진입점과 동의 변경 시 배너 해제를 확인합니다.
- Android의 로컬 Gradle 사용자 설정이나 CI 비밀 설정에 `ADMOB_APP_ID=ca-app-pub-...~...`를 지정합니다. `android/gradle.properties`에 넣어도 되지만 운영 설정을 검토하세요.
- 다음 빌드 인자로 실제 배너를 사용합니다. 게시하지 않고 검증하려면 테스트 기기를 등록하세요.

```powershell
flutter build appbundle --release --no-shrink --dart-define=PRODUCTION_ADS=true --dart-define=ADMOB_BANNER_ID=ca-app-pub-.../...
```

- iOS 실제 App ID는 `ios/Runner/Info.plist`의 `GADApplicationIdentifier`를 교체합니다. iOS용 별도 배너 ID가 필요합니다. ATT/광고 정책과 SKAdNetwork 설정을 확인해야 하며 iOS 출시는 이 작업에서 검증하지 않았습니다.
- UMP 실패·광고 네트워크 실패에서도 여행 데이터는 정상 작동해야 합니다. 개인정보 동의는 운영자/지역별로 검토해야 하며 테스트 ID를 실제 ID로 바꾸는 것만으로 정책 검증이 완료되지는 않습니다.

## Play 제출 전 남은 작업

- 운영자명/개인정보 문의처, 공개 개인정보처리방침 HTTPS URL을 확정하고 Play 등록정보 및 앱 안내를 갱신합니다.
- Google Mobile Ads SDK의 실제 데이터 수집/공유 항목, 목적, 암호화/삭제 정책, 광고 ID 사용을 최신 SDK 문서와 대조해 Data safety를 신고합니다. 로컬 여행 데이터를 서버에 올리지 않는다고 광고 SDK의 수집 항목까지 없다고 신고하면 안 됩니다.
- 대상 연령, 광고 포함 표시, 콘텐츠 등급, 앱 액세스(로그인 없음), 타깃 API와 SDK 정책을 제출 시점에 확인합니다.
- 물리 Android 기기(API 24, 26, 33, 34 이상 포함)에서 알림 권한 거절/허용, 앱 종료·재부팅·자정·시간대 변경·절전·여행 삭제와 만료를 테스트합니다. Ongoing 알림의 해제 불가능성을 보장하지 않습니다. 강제 종료 상태의 백그라운드 동작은 보장하지 않습니다.
- 오프라인·0예산·큰 금액·큰 글씨·화면 회전·한국어·다크모드·광고 실패를 검증합니다.
- 판매처/국가 콘텐츠와 공식 출처의 유효성을 다시 확인합니다. 제휴 링크를 추가하면 데이터와 고지 문구를 함께 수정합니다.
- 앱 아이콘과 스토어 스크린샷을 제작합니다. 현재 아이콘은 Flutter 템플릿 기본 아이콘으로 출시 전 교체해야 합니다.
- 내부/비공개 테스트 및 계정별 Play 테스트 요구사항을 완료하고 사용자가 게시를 승인한 뒤 제출합니다.

릴리스 코드 축소는 WorkManager 데이터베이스 생성자가 제거되어 앱이 시작할 때 종료되는 문제를 방지하기 위해 비활성화했습니다. 최적화 설정을 변경하는 경우 반드시 실제 릴리스 APK의 시작을 Android 기기에서 다시 검증하세요.
