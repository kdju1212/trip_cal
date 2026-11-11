'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const config = window.ADVERTISER_CONFIG || {};
  const state = {session: null, drafts: [], ads: [], filter: 'pending', busy: false, signed: new Map(), groups: [], campaigns: [], billingEnabled: false, mfaFactor: null, mfaPending: null, mfaAal: false, mfaRequired: null};
  const msg = value => { $('admin-message').textContent = value; };
  const headers = () => ({apikey: config.key, Authorization: `Bearer ${state.session.access_token}`});
  const node = (tag, text, className) => { const e = document.createElement(tag); if (text != null) e.textContent = text; if (className) e.className = className; return e; };
  const secureUrl = value => { try { const u = new URL(value); return u.protocol === 'https:' && !u.username && !u.password; } catch (_) { return false; } };
  function configured() {
    try { const u = new URL(config.url); return u.protocol === 'https:' && /^[a-z0-9-]+\.supabase\.co$/i.test(u.hostname) && !u.username && !u.password && (u.pathname === '/' || u.pathname === '') && !u.search && !u.hash && typeof config.key === 'string' && (config.key.startsWith('sb_publishable_') || config.key.split('.').length === 3); } catch (_) { return false; }
  }
  async function api(path, options = {}) {
    const response = await fetch(config.url.replace(/\/$/, '') + path, options);
    const text = await response.text(); let body;
    try { body = text ? JSON.parse(text) : null; } catch (_) { body = null; }
    if (!response.ok) { const error=new Error(body?.message || body?.error_description || '요청을 처리하지 못했어요.'); error.status=response.status; throw error; }
    return body;
  }
  function loggedIn(on) { $('admin-login').hidden = on; $('admin-workspace').hidden = !on; if (on) $('admin-account').textContent = state.session.user.email; }
  async function restoreAdmin() {
    if (!configured()) {
      $('admin-login-title').textContent = '서버 연결 필요';
      $('admin-login-help').textContent = '광고센터에서 서버 연결 설정을 확인해 주세요.';
      $('unified-login').hidden = false;
      return;
    }
    const saved = window.TripSession.read(config.url.replace(/\/$/, ''));
    if (!saved) {
      $('admin-login-title').textContent = '로그인이 필요해요';
      $('admin-login-help').textContent = '통합 로그인 후 관리자 센터로 이동해 주세요.';
      $('unified-login').hidden = false;
      return;
    }
    state.session = saved;
    try {
      const user = await api('/auth/v1/user', {headers: headers()});
      if (!user?.id) throw new Error('로그인 상태를 확인하지 못했어요.');
      state.session.user = user;
      window.TripSession.save(state.session, config.url.replace(/\/$/, ''));
      const permitted = await api('/rest/v1/rpc/is_ad_admin', {method:'POST', headers:{...headers(), 'Content-Type':'application/json'}, body:'{}'});
      if (permitted !== true) {
        state.session = null;
        $('admin-login-title').textContent = '관리자 권한이 없어요';
        $('admin-login-help').textContent = '광고주 센터를 이용하거나 관리자에게 권한을 문의해 주세요.';
        $('unified-login').textContent = '광고주 센터로 이동';
        $('unified-login').hidden = false;
        return;
      }
      loggedIn(true); msg(''); renderMfa(user); await loadAdminSecurity();
    } catch (_) {
      state.session = null;
      $('admin-login-title').textContent = '로그인을 확인하지 못했어요';
      $('admin-login-help').textContent = '연결 상태를 확인하고 통합 로그인에서 다시 로그인해 주세요.';
      $('unified-login').hidden = false;
    }
  }
  $('admin-logout').addEventListener('click', async () => {
    try { await api('/auth/v1/logout?scope=local', {method:'POST', headers:headers()}); } catch (_) { /* clear local session even offline */ }
    state.session = null; state.drafts = []; state.ads = []; state.mfaFactor = null; state.mfaPending = null; state.mfaRequired = null; $('admin-operations').hidden=true; $('mfa-secret').value = ''; state.signed.clear(); window.TripSession.clear();
    window.location.assign('index.html');
  });
  async function refresh() {
    if (!state.session) return;
    $('review-list').replaceChildren(node('p','불러오는 중이에요.','empty'));
    try {
      const [drafts, ads, groups, campaigns] = await Promise.all([
        api('/rest/v1/advertiser_drafts?select=id,group_id,merchant_name,title,description,sim_type,country_code,duration_days,price_krw,image_path,purchase_url,created_at,review_status,review_note,published_ad_id&deleted_at=is.null&order=created_at.desc&limit=200', {headers:headers()}),
        api('/rest/v1/sim_ads?select=id,is_active&limit=1000', {headers:headers()}),
        api('/rest/v1/ad_groups?select=id,campaign_id,name,cpc_bid_krw&limit=1000', {headers:headers()}),
        api('/rest/v1/ad_campaigns?select=id,name&limit=1000', {headers:headers()}),
      ]);
      state.drafts = drafts; state.ads = ads; state.groups = groups; state.campaigns = campaigns;
      $('pending-count').textContent = drafts.filter(d => d.review_status === 'pending').length;
      $('approved-count').textContent = drafts.filter(d => d.review_status === 'approved').length;
      render();
    } catch (_) { $('review-list').replaceChildren(node('p','광고를 불러오지 못했어요. 서버 설정을 확인하고 다시 시도해 주세요.','empty')); }
  }
  function readAal(token) {
    try { const part=token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'); return JSON.parse(atob(part.padEnd(Math.ceil(part.length/4)*4,'='))).aal === 'aal2'; } catch (_) { return false; }
  }
  function clearMfaForm() {
    state.mfaPending=null; $('mfa-secret').value=''; $('mfa-code').value=''; $('mfa-secret-section').hidden=true; $('mfa-form').hidden=true;
  }
  function renderMfa(user) {
    clearMfaForm();
    state.mfaFactor=(user?.factors || []).find(f => f.factor_type === 'totp' && f.status === 'verified') || null;
    state.mfaAal=readAal(state.session?.access_token || '');
    $('mfa-setup').hidden=!!state.mfaFactor || state.mfaAal;
    $('mfa-challenge').hidden=!state.mfaFactor || state.mfaAal;
    applyAdminSecurity();
    $('mfa-help').textContent=state.mfaAal ? '이 로그인에서 2단계 인증이 완료됐어요.' : state.mfaFactor ? '인증 앱의 번호를 입력하면 관리자 인증이 완료됩니다.' : '관리자 충전·환불을 위해 인증 앱을 설정해 주세요.';
  }
  function applyAdminSecurity() {
    const allowed=state.mfaRequired === false || (state.mfaRequired === true && state.mfaAal);
    $('admin-operations').hidden=!allowed;
    $('mfa-enforce').hidden=!(state.mfaRequired === false && state.mfaAal && state.mfaFactor);
  }
  async function loadAdminSecurity() {
    if (!state.session) return;
    state.mfaRequired=null; applyAdminSecurity();
    try {
      const result=await api('/rest/v1/rpc/admin_security_status',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:'{}'});
      if (!Array.isArray(result) || result.length!==1 || typeof result[0].mfa_required !== 'boolean') throw new Error('보안 상태 오류');
      state.mfaRequired=result[0].mfa_required; applyAdminSecurity();
      if (state.mfaRequired && !state.mfaAal) { $('mfa-message').textContent='관리자 업무를 보려면 2단계 인증을 완료해 주세요.'; return; }
      await refresh(); await Promise.all([loadWallets(),loadRefunds(),loadAudit(),loadCorrections()]);
    } catch (_) { state.mfaRequired=null; applyAdminSecurity(); $('mfa-message').textContent='관리자 보안 상태를 확인하지 못했어요. 새로고침해 주세요.'; }
  }
  $('mfa-enforce').addEventListener('click', async () => {
    if (!state.session || !state.mfaAal || !state.mfaFactor || state.mfaRequired !== false) return;
    if (!window.confirm('모든 관리자에게 2단계 인증을 필수로 적용할까요? 인증 앱을 잃으면 관리자 접근 복구가 필요할 수 있습니다.')) return;
    const button=$('mfa-enforce'); button.disabled=true; $('mfa-message').textContent='보안 설정을 적용하고 있어요.';
    try {
      await api('/rest/v1/rpc/enable_admin_mfa_enforcement',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:'{}'});
      await loadAdminSecurity(); $('mfa-message').textContent='관리자 2단계 인증을 필수로 설정했어요.';
    } catch (_) { $('mfa-message').textContent='보안 설정을 적용하지 못했어요. 다시 인증한 뒤 시도해 주세요.'; }
    finally { button.disabled=false; }
  });
  $('mfa-setup').addEventListener('click', async () => {
    if (!state.session || state.mfaPending) return;
    const button=$('mfa-setup'); button.disabled=true; $('mfa-message').textContent='설정 키를 준비하고 있어요.';
    try {
      const result=await api('/auth/v1/factors',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:JSON.stringify({factor_type:'totp',friendly_name:'여행 광고센터',issuer:'여행 준비 도우미'})});
      if (!result?.id || !result?.totp?.secret || typeof result.totp.secret !== 'string') throw new Error('설정 정보를 확인하지 못했어요.');
      state.mfaPending=result.id; $('mfa-secret').value=result.totp.secret; $('mfa-secret-section').hidden=false; $('mfa-form').hidden=false; button.hidden=true; $('mfa-message').textContent='';
    } catch (_) { $('mfa-message').textContent='인증 앱 설정을 시작하지 못했어요. 서버 설정을 확인해 주세요.'; }
    finally { button.disabled=false; }
  });
  $('mfa-challenge').addEventListener('click', () => {
    if (!state.mfaFactor) return;
    state.mfaPending=state.mfaFactor.id; $('mfa-secret-section').hidden=true; $('mfa-form').hidden=false; $('mfa-challenge').hidden=true; $('mfa-message').textContent='';
  });
  $('mfa-copy').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText($('mfa-secret').value); $('mfa-message').textContent='설정 키를 복사했어요. 인증 앱에만 붙여 넣어 주세요.'; }
    catch (_) { $('mfa-message').textContent='설정 키를 직접 길게 눌러 복사해 주세요.'; }
  });
  $('mfa-cancel').addEventListener('click', async () => {
    // Unverified setup is removed only when the user explicitly cancels it.
    const pending=state.mfaPending; const enrolling=!state.mfaFactor && !!pending;
    if (enrolling) {
      try { await api(`/auth/v1/factors/${encodeURIComponent(pending)}`,{method:'DELETE',headers:headers()}); }
      catch (_) { $('mfa-message').textContent='설정 취소를 완료하지 못했어요. 다시 시도해 주세요.'; return; }
    }
    renderMfa(state.session?.user); $('mfa-message').textContent='';
  });
  $('mfa-form').addEventListener('submit', async event => {
    event.preventDefault(); const factor=state.mfaPending, code=$('mfa-code').value.trim();
    if (!state.session || !factor || !/^[0-9]{6}$/.test(code) || $('mfa-verify').disabled) return;
    const button=$('mfa-verify'); button.disabled=true; $('mfa-message').textContent='인증하고 있어요.';
    try {
      const challenge=await api(`/auth/v1/factors/${encodeURIComponent(factor)}/challenge`,{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:'{}'});
      if (!challenge?.id) throw new Error('인증 요청 실패');
      const result=await api(`/auth/v1/factors/${encodeURIComponent(factor)}/verify`,{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:JSON.stringify({challenge_id:challenge.id,code})});
      if (!result?.access_token || !readAal(result.access_token)) throw new Error('2단계 인증 확인 실패');
      const previousUser=state.session.user; state.session={...result,user:result.user || previousUser};
      const stored=window.TripSession.save(state.session,config.url.replace(/\/$/,''));
      let user=state.session.user;
      try { user=await api('/auth/v1/user',{headers:headers()}); state.session.user=user; window.TripSession.save(state.session,config.url.replace(/\/$/,'')); } catch (_) { /* authentication succeeded; refresh the profile later */ }
      renderMfa(user); await loadAdminSecurity(); $('mfa-message').textContent=stored ? '2단계 인증을 완료했어요.' : '인증은 완료됐지만 브라우저에 로그인 상태를 저장할 수 없어 화면 이동 시 다시 로그인해야 해요.';
    } catch (_) { $('mfa-code').value=''; $('mfa-message').textContent='인증번호를 확인하고 다시 시도해 주세요.'; }
    finally { button.disabled=false; }
  });
  async function loadWallets() {
    if (!state.session) return;
    const help=$('wallet-help'), message=$('wallet-message');
    for (const id of ['wallet-owner','wallet-amount','wallet-reference','wallet-submit']) $(id).disabled=true;
    help.textContent='잔액 정보를 불러오고 있어요.'; message.textContent='';
    try {
      const enabled=await api('/rest/v1/rpc/ad_billing_enabled',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:'{}'});
      if (typeof enabled !== 'boolean') throw new Error('과금 상태를 확인할 수 없어요.');
      state.billingEnabled=enabled;
      if (!enabled) { help.textContent='유료 과금 준비 중입니다. 입금을 받거나 잔액을 충전할 수 없어요.'; return; }
      if (!state.mfaAal) { help.textContent='잔액 확인과 충전에는 관리자 2단계 인증이 필요해요.'; return; }
      const wallets=await api('/rest/v1/rpc/list_advertiser_wallets',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:'{}'});
      if (!Array.isArray(wallets)) throw new Error('잔액 정보를 확인할 수 없어요.');
      const select=$('wallet-owner'), previous=select.value; select.replaceChildren();
      const empty=node('option','광고주 선택'); empty.value=''; select.append(empty);
      for (const wallet of wallets) { const option=node('option',`${wallet.email || '계정'} · 잔액 ${Number(wallet.balance_krw).toLocaleString('ko-KR')}원`); option.value=wallet.owner_id; select.append(option); }
      if (wallets.some(w=>w.owner_id===previous)) select.value=previous;
      help.textContent=enabled ? '입금을 확인한 후 거래 고유번호로 충전하세요.' : '유료 과금 준비 중입니다. 입금을 받거나 잔액을 충전할 수 없어요.';
      for (const id of ['wallet-owner','wallet-amount','wallet-reference','wallet-submit']) $(id).disabled=!(enabled && state.mfaAal);
      if (enabled && !state.mfaAal) help.textContent='충전하려면 관리자 2단계 인증이 필요해요.';
    } catch (_) { state.billingEnabled=false; help.textContent='잔액 정보를 불러오지 못했어요. 새로고침해 주세요.'; }
  }
  async function receiptKey(value) {
    const bytes=new TextEncoder().encode(value.trim().toLowerCase());
    const digest=new Uint8Array(await crypto.subtle.digest('SHA-256',bytes));
    const hex=Array.from(digest.slice(0,16),b=>b.toString(16).padStart(2,'0')).join('');
    return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
  }
  $('wallet-refresh').addEventListener('click', loadWallets);
  $('wallet-form').addEventListener('submit', async event => {
    event.preventDefault();
    if (!state.session || !state.billingEnabled || !state.mfaAal || $('wallet-submit').disabled) return;
    const owner=$('wallet-owner').value, amount=Number($('wallet-amount').value), receipt=$('wallet-reference').value.trim();
    if (!owner || !Number.isSafeInteger(amount) || amount<1 || amount>1000000000 || receipt.length<3 || receipt.length>80) { $('wallet-message').textContent='광고주, 금액과 입금 거래 고유번호를 확인해 주세요.'; return; }
    const recipient=$('wallet-owner').selectedOptions?.[0]?.textContent || '선택한 광고주';
    if (!window.confirm(`광고주: ${recipient}\n거래 번호: ${receipt}\n입금 확인 금액: ${amount.toLocaleString('ko-KR')}원\n\n확인한 입금을 충전할까요?`)) return;
    const button=$('wallet-submit'); button.disabled=true; $('wallet-message').textContent='충전 중이에요.';
    try {
      const reference=await receiptKey(receipt);
      await api('/rest/v1/rpc/confirm_manual_ad_topup',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:JSON.stringify({p_owner:owner,p_amount:amount,p_reference:reference,p_note:receipt})});
      $('wallet-form').reset(); await loadWallets(); $('wallet-message').textContent='입금을 확인하고 충전했어요.';
    } catch (_) { $('wallet-message').textContent='충전 결과를 확인하지 못했어요. 같은 거래 번호를 유지하고 잔액을 확인해 주세요.'; }
    finally { button.disabled=!(state.billingEnabled && state.mfaAal); }
  });
  async function loadAudit() {
    const list=$('audit-list');
    if (!state.session || !state.mfaAal) { list.textContent='관리자 2단계 인증 후 확인할 수 있어요.'; return; }
    list.textContent='변경 이력을 불러오고 있어요.';
    try {
      const rows=await api('/rest/v1/rpc/list_ad_action_audit',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:'{}'});
      if (!Array.isArray(rows)) throw new Error('invalid response');
      list.replaceChildren();
      if (!rows.length) { list.textContent='아직 기록된 변경 이력이 없어요.'; return; }
      const kinds={ad_campaigns:'캠페인',ad_groups:'광고그룹',advertiser_drafts:'소재',sim_ads:'앱 광고',ad_security_settings:'관리자 보안'};
      const actions={admin_mfa_required:'2단계 인증 필수 설정',created:'생성',review_status:'검수 상태 변경',advertiser_enabled:'켜기·끄기 변경',deleted_at:'삭제',is_active:'노출 상태 변경',daily_budget_krw:'일 예산 변경',cpc_bid_krw:'입찰가 변경',price_krw:'상품 가격 변경',name:'이름 변경',merchant_name:'업체명 변경',title:'제목 변경',description:'설명 변경',purchase_url:'구매 링크 변경',image_path:'이미지 변경',sim_type:'유심 종류 변경',country_code:'국가 변경',duration_days:'사용 일수 변경'};
      for (const entry of rows) {
        const item=entry.entity_kind === 'ad_campaigns' ? state.campaigns.find(x=>x.id===entry.entity_id)?.name : entry.entity_kind === 'ad_groups' ? state.groups.find(x=>x.id===entry.entity_id)?.name : entry.entity_kind === 'advertiser_drafts' ? state.drafts.find(x=>x.id===entry.entity_id)?.title : entry.entity_kind === 'sim_ads' ? state.drafts.find(x=>String(x.published_ad_id)===entry.entity_id)?.title : '';
        const name=item || (entry.entity_kind === 'ad_security_settings' ? '전체 관리자' : `항목 ${String(entry.entity_id || '').slice(0,8)}`);
        const row=node('div',null,'audit-row'), title=node('strong',`${kinds[entry.entity_kind] || '광고'} · ${name} · ${actions[entry.action] || '변경'}`);
        const when=new Date(entry.created_at); const date=Number.isNaN(when.getTime()) ? '' : when.toLocaleString('ko-KR',{timeZone:'Asia/Seoul'});
        const meta=node('small',[entry.actor_email || '시스템',date].filter(Boolean).join(' · ')); row.append(title,meta);
        if (['daily_budget_krw','cpc_bid_krw','price_krw'].includes(entry.action)) {
          const fmt=value => value == null ? '미설정' : `${Number(value).toLocaleString('ko-KR')}원`;
          row.append(node('small',`${fmt(entry.detail?.before)} → ${fmt(entry.detail?.after)}`));
        }
        list.append(row);
      }
    } catch (_) { list.textContent='이력을 불러오지 못했어요. 인증과 연결 상태를 확인해 주세요.'; }
  }
  $('audit-refresh').addEventListener('click',loadAudit);
  async function loadRefunds() {
    const list=$('refund-list');
    if (!state.session || !state.mfaAal) { list.textContent='관리자 2단계 인증 후 확인할 수 있어요.'; return; }
    list.textContent='차감 내역을 불러오고 있어요.';
    try {
      const rows=await api('/rest/v1/rpc/list_ad_debits_for_refund',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:'{}'});
      if (!Array.isArray(rows)) throw new Error('invalid response');
      list.replaceChildren();
      if (!rows.length) { list.textContent='환불할 차감 내역이 없어요.'; return; }
      for (const entry of rows) {
        const row=node('div',null,'refund-row'), content=node('div'), name=node('strong',entry.ad_title || '광고 클릭'), detail=node('small',`${entry.email || '광고주'} · ${entry.campaign || '캠페인'} · ${Number(entry.amount_krw).toLocaleString('ko-KR')}원`);
        content.append(name,detail); row.append(content);
        if (entry.refunded) row.append(node('span','환불 완료','status-note'));
        else { const button=node('button','환불','secondary'); button.type='button'; button.addEventListener('click',()=>refundClick(entry,button)); row.append(button); }
        list.append(row);
      }
    } catch (_) { list.textContent='차감 내역을 불러오지 못했어요. 인증과 연결 상태를 확인해 주세요.'; }
  }
  async function refundClick(entry,button) {
    if (!state.session || !state.mfaAal || button.disabled) return;
    const reason=window.prompt('환불 사유를 3자 이상 입력해 주세요.');
    if (reason === null) return;
    if (reason.trim().length<3 || reason.trim().length>100) { $('refund-message').textContent='환불 사유는 3~100자로 입력해 주세요.'; return; }
    if (!window.confirm(`광고주: ${entry.email || '계정'}\n소재: ${entry.ad_title || '광고 클릭'}\n환불 금액: ${Number(entry.amount_krw).toLocaleString('ko-KR')}원\n\n이 차감 내역을 환불할까요?`)) return;
    button.disabled=true; $('refund-message').textContent='환불 처리 중이에요.';
    try {
      const result=await api('/rest/v1/rpc/refund_ad_click',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:JSON.stringify({p_debit_id:entry.debit_id,p_reason:reason.trim()})});
      $('refund-message').textContent=result==='already_refunded' ? '이미 환불된 클릭입니다.' : '환불을 기록하고 잔액에 반영했어요.';
      await Promise.all([loadRefunds(),loadWallets()]);
    } catch (_) { $('refund-message').textContent='환불 결과를 확인하지 못했어요. 목록을 새로고침하고 다시 확인해 주세요.'; }
    finally { button.disabled=false; }
  }
  $('refund-refresh').addEventListener('click',loadRefunds);
  // Keep the same request ID across an uncertain response or a page reload.
  // The server checks it against the original operation before making changes.
  const correctionKey='trip_ad_finance_pending_v1';
  function pendingCorrection() {
    try { const item=JSON.parse(sessionStorage.getItem(correctionKey) || 'null'); return item && item.user === state.session?.user?.id ? item : null; } catch (_) { return null; }
  }
  async function loadCorrections() {
    const list=$('correction-list');
    if (!state.session || !state.mfaAal) { list.textContent='관리자 2단계 인증 후 확인할 수 있어요.'; return; }
    const pending=pendingCorrection(); $('correction-retry').hidden=!pending;
    if (pending) $('correction-message').textContent='이전 요청의 결과를 먼저 확인해 주세요. 같은 요청 번호로 안전하게 다시 확인합니다.';
    list.textContent='내역을 불러오고 있어요.';
    try {
      const entries=await api('/rest/v1/rpc/list_ad_corrections',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:'{}'});
      if (!Array.isArray(entries)) throw new Error('invalid response');
      list.replaceChildren();
      if (!entries.length) { list.textContent='충전 또는 차감 내역이 없어요.'; return; }
      for (const entry of entries) {
        const row=node('div',null,'refund-row'), content=node('div');
        const remaining=Number(entry.remaining_krw), amount=Number(entry.amount_krw);
        content.append(node('strong',entry.kind === 'debit' ? '광고 클릭 차감' : '입금 충전'),node('small',`${entry.email || '광고주'} · ${amount.toLocaleString('ko-KR')}원 · ${entry.kind === 'debit' ? '환불 가능' : '취소 가능'} ${remaining.toLocaleString('ko-KR')}원`));
        row.append(content);
        if (remaining>0 && !pending) { const button=node('button',entry.kind === 'debit' ? '부분 환불' : '충전 취소','secondary'); button.type='button'; button.addEventListener('click',()=>startCorrection(entry,button)); row.append(button); }
        else if (remaining<=0) row.append(node('span','처리 완료','status-note'));
        list.append(row);
      }
    } catch (_) { list.textContent='내역을 불러오지 못했어요. 인증과 연결 상태를 확인해 주세요.'; }
  }
  async function startCorrection(entry,button) {
    if (!state.session || !state.mfaAal || pendingCorrection() || button.disabled) return;
    const amount=entry.kind === 'debit' ? window.prompt(`환불할 금액을 원 단위로 입력해 주세요. 최대 ${Number(entry.remaining_krw).toLocaleString('ko-KR')}원`) : String(entry.amount_krw);
    if (amount === null) return;
    if (!/^[0-9]+$/.test(amount) || !Number.isSafeInteger(Number(amount)) || Number(amount)<1 || Number(amount)>Number(entry.remaining_krw)) { $('correction-message').textContent='처리 가능한 금액을 확인해 주세요.'; return; }
    const reason=window.prompt('처리 사유를 3~100자로 입력해 주세요.');
    if (reason === null) return;
    if (reason.trim().length<3 || reason.trim().length>100) { $('correction-message').textContent='사유는 3~100자로 입력해 주세요.'; return; }
    if (!window.confirm(`${entry.email || '광고주'} · ${Number(amount).toLocaleString('ko-KR')}원\n${entry.kind === 'debit' ? '부분 환불' : '충전 취소'}을 처리할까요?`)) return;
    const item={user:state.session.user.id,kind:entry.kind,id:entry.entry_id,amount:Number(amount),reason:reason.trim(),request:crypto.randomUUID()};
    try { sessionStorage.setItem(correctionKey,JSON.stringify(item)); if (!pendingCorrection()) throw new Error('storage'); }
    catch (_) { $('correction-message').textContent='요청 번호를 안전하게 저장할 수 없어 처리하지 않았어요.'; return; }
    await sendCorrection(item);
  }
  async function sendCorrection(item) {
    if (!state.session || !state.mfaAal || item.user!==state.session.user.id) return;
    $('correction-retry').disabled=true; $('correction-message').textContent='처리 결과를 확인하고 있어요.';
    const debit=item.kind === 'debit';
    const payload=debit ? {p_debit_id:item.id,p_amount:item.amount,p_request_id:item.request,p_reason:item.reason} : {p_credit_id:item.id,p_request_id:item.request,p_reason:item.reason};
    try {
      const result=await api(`/rest/v1/rpc/${debit ? 'partial_ad_click_refund' : 'reverse_ad_topup'}`,{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:JSON.stringify(payload)});
      if (!['refunded','reversed','already_processed','already_reversed'].includes(result)) throw new Error('unknown result');
      sessionStorage.removeItem(correctionKey); $('correction-message').textContent='처리 결과를 확인했어요.';
      await Promise.all([loadCorrections(),loadRefunds(),loadWallets()]);
    } catch (error) {
      if ([400,403,422].includes(error.status)) { sessionStorage.removeItem(correctionKey); $('correction-retry').hidden=true; $('correction-message').textContent='요청이 거절되어 처리되지 않았어요. 금액과 잔액을 확인해 주세요.'; await loadCorrections(); }
      else { $('correction-retry').hidden=false; $('correction-message').textContent='처리 결과를 확인하지 못했어요. 같은 요청으로 다시 확인해 주세요.'; }
    }
    finally { $('correction-retry').disabled=false; }
  }
  $('correction-retry').addEventListener('click',()=>{ const item=pendingCorrection(); if (item) return sendCorrection(item); });
  $('correction-refresh').addEventListener('click',loadCorrections);
  $('admin-refresh').addEventListener('click', refresh);
  document.querySelectorAll('[data-filter]').forEach(button => button.addEventListener('click', () => {
    state.filter = button.dataset.filter;
    document.querySelectorAll('[data-filter]').forEach(b => b.classList.toggle('active', b === button)); render();
  }));
  async function signedImage(path) {
    if (!state.signed.has(path) || state.signed.get(path).expires <= Date.now()) {
      const encoded = path.split('/').map(encodeURIComponent).join('/');
      const result = await api(`/storage/v1/object/sign/ad-draft-images/${encoded}`, {method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:JSON.stringify({expiresIn:300})});
      if (!result?.signedURL?.startsWith('/object/sign/')) throw new Error('이미지를 불러오지 못했어요.');
      state.signed.set(path, {url: config.url.replace(/\/$/,'') + '/storage/v1' + result.signedURL, expires: Date.now() + 240000});
    }
    return state.signed.get(path).url;
  }
  function render() {
    const list = $('review-list'); list.replaceChildren();
    const matches = state.drafts.filter(d => d.review_status === state.filter);
    if (!matches.length) { list.append(node('p','해당하는 광고가 없어요.','empty')); return; }
    for (const draft of matches) {
      const card = node('article',null,'review-card');
      const head = node('div',null,'review-head');
      head.append(node('strong',draft.merchant_name), node('span',({pending:'검토 대기',approved:'승인',rejected:'반려'})[draft.review_status],`status ${draft.review_status}`));
      const body = node('div',null,'review-body'), image = document.createElement('img'); image.className='review-image'; image.alt='광고 상품 이미지';
      signedImage(draft.image_path).then(url => { if (card.isConnected) image.src=url; }).catch(() => { image.alt='이미지를 불러올 수 없음'; });
      const info = node('div'); info.append(node('h3',draft.title),node('p',draft.description));
      if (draft.price_krw != null) info.append(node('strong',`등록 가격 ${Number(draft.price_krw).toLocaleString('ko-KR')}원`));
      body.append(image,info);
      const meta=node('div',null,'review-meta'); for(const value of [draft.country_code, draft.sim_type === 'esim' ? 'eSIM' : '유심', `${draft.duration_days}일`]) meta.append(node('span',value));
      card.append(head,body,meta);
      const group=state.groups.find(g => g.id === draft.group_id);
      if (group) {
        const campaign=state.campaigns.find(c => c.id === group.campaign_id);
        card.append(node('p',`캠페인: ${campaign?.name || '확인 불가'} · 광고그룹: ${group.name} · 설정 입찰가: ${Number(group.cpc_bid_krw).toLocaleString('ko-KR')}원 (새 앱부터 입찰가 순위 적용)`,'status-note'));
      }
      if (secureUrl(draft.purchase_url)) { const link=node('a','판매처 링크 확인 ↗'); link.href=draft.purchase_url; link.target='_blank'; link.rel='noopener noreferrer'; card.append(link); }
      if (draft.review_note) card.append(node('p',`검수 의견: ${draft.review_note}`,'status-note'));
      const actions=node('div',null,'review-actions');
      if (draft.review_status === 'pending') {
        const approve=node('button','승인 후 노출'); approve.type='button'; approve.addEventListener('click',()=>review(draft,true));
        const reject=node('button','반려','danger'); reject.type='button'; reject.addEventListener('click',()=>showReject(card,draft)); actions.append(approve,reject);
      } else if (draft.review_status === 'approved' && draft.published_ad_id != null) {
        const ad=state.ads.find(a => a.id === draft.published_ad_id);
        if (ad) { const toggle=node('button',ad.is_active ? '노출 중지' : '다시 노출','secondary'); toggle.type='button'; toggle.addEventListener('click',()=>toggleAd(ad)); actions.append(toggle); }
      }
      card.append(actions); list.append(card);
    }
  }
  function showReject(card,draft) {
    if (card.querySelector('.reason')) return;
    const wrap=node('div',null,'reason'); const label=node('label','반려 사유'); const input=document.createElement('textarea'); input.maxLength=300; input.placeholder='광고주에게 전달할 사유를 입력해 주세요.'; label.append(input);
    const send=node('button','반려 확정','danger'); send.type='button'; send.addEventListener('click',()=>{ if(!input.value.trim()){msg('반려 사유를 입력해 주세요.');return;} review(draft,false,input.value.trim()); });
    wrap.append(label,send);card.append(wrap);input.focus();
  }
  async function review(draft, approve, note='') {
    if (state.busy) return;
    state.busy=true; msg(approve ? '광고를 승인하고 있어요.' : '반려를 저장하고 있어요.');
    let publicPath=null;
    try {
      if (approve) {
        if (!secureUrl(draft.purchase_url)) throw new Error('구매 링크가 올바른 https 주소인지 확인해 주세요.');
        const imageUrl=await signedImage(draft.image_path), response=await fetch(imageUrl);
        if (!response.ok) throw new Error('검수 이미지를 불러오지 못했어요.');
        const blob=await response.blob(); if(!['image/jpeg','image/png','image/webp'].includes(blob.type) || blob.size>3145728 || !(await window.TripImageRatio.isSquare(blob))) throw new Error('이미지는 3MB 이하의 1:1 정사각형 JPG, PNG, WEBP 파일이어야 합니다.');
        const ext={'image/jpeg':'jpg','image/png':'png','image/webp':'webp'}[blob.type]; publicPath=`${draft.id}/${crypto.randomUUID()}.${ext}`;
        await api(`/storage/v1/object/ad-published-images/${publicPath}`,{method:'POST',headers:{...headers(),'Content-Type':blob.type,'x-upsert':'false'},body:blob});
      }
      await api('/rest/v1/rpc/review_advertisement',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:JSON.stringify({p_draft_id:draft.id,p_approved:approve,p_image_path:publicPath,p_note:note})});
      msg(approve?'승인한 광고를 앱에 노출합니다.':'광고를 반려했어요.'); await refresh();
    } catch (err) {
      msg(err.message || '처리 결과를 확인하지 못했어요. 새로고침 후 상태를 확인해 주세요.');
    } finally {state.busy=false;}
  }
  async function toggleAd(ad) {
    if(state.busy)return;state.busy=true;
    try{await api('/rest/v1/rpc/set_ad_active',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:JSON.stringify({p_ad_id:ad.id,p_active:!ad.is_active})});msg(ad.is_active?'광고 노출을 중지했어요.':'광고를 다시 노출합니다.');await refresh();}
    catch(err){msg(err.message || '변경하지 못했어요.');}finally{state.busy=false;}
  }
  restoreAdmin();
})();
