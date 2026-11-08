'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const config = window.ADVERTISER_CONFIG || {};
  const state = {session: null, drafts: [], ads: [], filter: 'pending', busy: false, signed: new Map()};
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
  $('login-form').addEventListener('submit', async e => {
    e.preventDefault();
    if (!configured()) { msg('서버 연결 정보가 설정되지 않았어요.'); return; }
    msg('로그인 중이에요.');
    try {
      const keyHeaders = {apikey: config.key, 'Content-Type': 'application/json'};
      if (!config.key.startsWith('sb_publishable_')) keyHeaders.Authorization = `Bearer ${config.key}`;
      const session = await api('/auth/v1/token?grant_type=password', {method:'POST', headers:keyHeaders, body:JSON.stringify({email:$('admin-email').value.trim(), password:$('admin-password').value})});
      $('admin-password').value = '';
      if (!session?.access_token || !session?.user) throw new Error('로그인 정보를 확인해 주세요.');
      state.session = session;
      const permitted = await api('/rest/v1/rpc/is_ad_admin', {method:'POST', headers:{...headers(), 'Content-Type':'application/json'}, body:'{}'});
      if (permitted !== true) { state.session = null; throw new Error('이 계정에 관리자 권한이 없습니다.'); }
      loggedIn(true); msg(''); await refresh();
    } catch (err) { state.session = null; loggedIn(false); msg(err.message || '로그인하지 못했어요.'); }
  });
  $('admin-logout').addEventListener('click', async () => {
    try { await api('/auth/v1/logout', {method:'POST', headers:headers()}); } catch (_) { /* clear local session even offline */ }
    state.session = null; state.drafts = []; state.ads = []; state.signed.clear(); loggedIn(false); msg('로그아웃했어요.');
  });
  async function refresh() {
    if (!state.session) return;
    $('review-list').replaceChildren(node('p','불러오는 중이에요.','empty'));
    try {
      const [drafts, ads] = await Promise.all([
        api('/rest/v1/advertiser_drafts?select=id,merchant_name,title,description,sim_type,country_code,duration_days,price_krw,image_path,purchase_url,created_at,review_status,review_note,published_ad_id&order=created_at.desc&limit=200', {headers:headers()}),
        api('/rest/v1/sim_ads?select=id,is_active&limit=1000', {headers:headers()}),
      ]);
      state.drafts = drafts; state.ads = ads;
      $('pending-count').textContent = drafts.filter(d => d.review_status === 'pending').length;
      $('approved-count').textContent = drafts.filter(d => d.review_status === 'approved').length;
      render();
    } catch (_) { $('review-list').replaceChildren(node('p','광고를 불러오지 못했어요. 서버 설정을 확인하고 다시 시도해 주세요.','empty')); }
  }
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
})();
