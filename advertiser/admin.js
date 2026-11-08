'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const config = window.ADVERTISER_CONFIG || {};
  const state = {session: null, drafts: [], ads: [], filter: 'pending', busy: false, signed: new Map(), groups: [], campaigns: [], billingEnabled: false};
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
    if (!response.ok) throw new Error(body?.message || body?.error_description || '요청을 처리하지 못했어요.');
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
      loggedIn(true); msg(''); await Promise.all([refresh(), loadWallets()]);
    } catch (_) {
      state.session = null;
      $('admin-login-title').textContent = '로그인을 확인하지 못했어요';
      $('admin-login-help').textContent = '연결 상태를 확인하고 통합 로그인에서 다시 로그인해 주세요.';
      $('unified-login').hidden = false;
    }
  }
  $('admin-logout').addEventListener('click', async () => {
    try { await api('/auth/v1/logout?scope=local', {method:'POST', headers:headers()}); } catch (_) { /* clear local session even offline */ }
    state.session = null; state.drafts = []; state.ads = []; state.signed.clear(); window.TripSession.clear();
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
  async function loadWallets() {
    if (!state.session) return;
    const help=$('wallet-help'), message=$('wallet-message');
    for (const id of ['wallet-owner','wallet-amount','wallet-reference','wallet-submit']) $(id).disabled=true;
    help.textContent='잔액 정보를 불러오고 있어요.'; message.textContent='';
    try {
      const [enabled, wallets]=await Promise.all([
        api('/rest/v1/rpc/ad_billing_enabled',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:'{}'}),
        api('/rest/v1/rpc/list_advertiser_wallets',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:'{}'}),
      ]);
      if (typeof enabled !== 'boolean' || !Array.isArray(wallets)) throw new Error('잔액 정보를 확인할 수 없어요.');
      state.billingEnabled=enabled;
      const select=$('wallet-owner'), previous=select.value; select.replaceChildren();
      const empty=node('option','광고주 선택'); empty.value=''; select.append(empty);
      for (const wallet of wallets) { const option=node('option',`${wallet.email || '계정'} · 잔액 ${Number(wallet.balance_krw).toLocaleString('ko-KR')}원`); option.value=wallet.owner_id; select.append(option); }
      if (wallets.some(w=>w.owner_id===previous)) select.value=previous;
      help.textContent=enabled ? '입금을 확인한 후 거래 고유번호로 충전하세요.' : '유료 과금 준비 중입니다. 입금을 받거나 잔액을 충전할 수 없어요.';
      for (const id of ['wallet-owner','wallet-amount','wallet-reference','wallet-submit']) $(id).disabled=!enabled;
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
    if (!state.session || !state.billingEnabled || $('wallet-submit').disabled) return;
    const owner=$('wallet-owner').value, amount=Number($('wallet-amount').value), receipt=$('wallet-reference').value.trim();
    if (!owner || !Number.isSafeInteger(amount) || amount<1 || amount>1000000000 || receipt.length<3 || receipt.length>80) { $('wallet-message').textContent='광고주, 금액과 입금 거래 고유번호를 확인해 주세요.'; return; }
    if (!window.confirm(`입금 확인 후 ${amount.toLocaleString('ko-KR')}원을 이 광고주에게 충전할까요?`)) return;
    const button=$('wallet-submit'); button.disabled=true; $('wallet-message').textContent='충전 중이에요.';
    try {
      const reference=await receiptKey(receipt);
      await api('/rest/v1/rpc/confirm_manual_ad_topup',{method:'POST',headers:{...headers(),'Content-Type':'application/json'},body:JSON.stringify({p_owner:owner,p_amount:amount,p_reference:reference,p_note:receipt})});
      $('wallet-form').reset(); await loadWallets(); $('wallet-message').textContent='입금을 확인하고 충전했어요.';
    } catch (_) { $('wallet-message').textContent='충전 결과를 확인하지 못했어요. 같은 거래 번호를 유지하고 잔액을 확인해 주세요.'; }
    finally { button.disabled=!state.billingEnabled; }
  });
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
        const imageUrl=await signedImage(draft.image_path), response=await fetch(imageUrl);
        if (!response.ok) throw new Error('검수 이미지를 불러오지 못했어요.');
        const blob=await response.blob(); if(!['image/jpeg','image/png','image/webp'].includes(blob.type) || blob.size>3145728) throw new Error('이미지 형식 또는 크기를 확인해 주세요.');
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
