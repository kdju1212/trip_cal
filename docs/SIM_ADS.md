# 유심·eSIM 업체 광고 설정

앱은 Supabase PostgREST에서 광고 상품을 읽습니다. 프로젝트 생성 및 상품 등록은 별도로 필요하며, 연결되지 않으면 광고 없이 기존 쇼핑 검색을 보여줍니다. 계정 생성, 프로젝트 생성, SQL 적용과 결제 설정은 자동으로 수행되지 않습니다.

## 설정

1. Supabase 프로젝트를 만들고 `supabase/migrations/202611080001_sim_ads.sql`을 SQL Editor에서 실행합니다. 실행 전 SQL을 검토하세요.
2. 프로젝트 URL과 **공개용** anon 또는 publishable 키를 준비합니다. `service_role`, secret 키나 DB 비밀번호를 앱, Git, 빌드 인자에 넣지 마세요. 클라이언트 키는 앱에서 추출할 수 있습니다.
3. GitHub 저장소의 Actions variables `SUPABASE_URL`, `SUPABASE_ANON_KEY`를 설정하거나 다음처럼 빌드합니다.

   ```sh
   flutter build apk --release --no-shrink --split-per-abi \
     --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_KEY
   ```

4. 대시보드 Table Editor에서 `sim_ads`에 광고주명, 상품명, `sim_type` (`sim` 또는 `esim`), ISO 국가 코드(예: `JP`), 실제 이용 일수, 가격(원), HTTPS 구매 링크를 등록합니다. 이미지 URL은 HTTPS만 사용합니다. 공개 준비가 완료되면 `is_active`를 true로 설정합니다. 시작·종료 시간을 선택적으로 설정할 수 있습니다. 현재 시점에 활성화된 상품만 공개됩니다.
5. 앱에서는 여행 국가·종류·일수와 정확히 일치하는 상품을 가져옵니다. 여행 날짜가 없으면 해당 국가와 종류의 모든 일수를 표시합니다. 상품을 누르면 외부 구매 링크가 열립니다. 관리자용 등록 화면은 제공하지 않으며 Supabase 대시보드로 관리합니다.

## 운영 시 확인

- 상품 가격과 조건, 링크의 유효성을 관리자가 확인하고 갱신해야 합니다. 가격은 등록값이며 실시간 가격이 아닙니다.
- RLS 정책은 활성화된 행의 지정된 열만 공개합니다. 익명 사용자는 등록·수정·삭제를 할 수 없습니다. 광고주 연락처나 내부 계약정보 같은 비공개 정보는 이 공개 테이블에 넣지 마세요.
- 이미지가 외부 URL이면 해당 서버가 사용자 IP를 받을 수 있습니다. Supabase 접속과 외부 이미지·판매처 이동에 관한 내용을 실제 운영 환경에 맞춰 개인정보처리방침에 반영하세요.
- 앱은 광고 항목에 `광고`를 표시하며 제휴 링크 사용 여부와 사업자 표시, 광고 표시에 필요한 사항은 실제 계약과 운영 환경에 맞게 정리하세요.
