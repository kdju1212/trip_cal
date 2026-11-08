'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const state = { url: '', key: '', session: null, admin: false, previewUrl: null };
  const demo = new URLSearchParams(location.search).get('preview') === '1';
  const message = text => { $('message').textContent = text; };
  const show = (id, visible) => { $(id).hidden = !visible; };
  const https = value => { try { const u = new URL(value); return u.protocol === 'https:' && !u.username && !u.password; } catch (_) { return false; } };
  const configValid = (url, key) => {
    try {
      const u = new URL(url);
      if (!key || key.startsWith('sb_secret_')) return false;
      if (!key.startsWith('sb_publishable_')) {
        const encoded = key.split('.')[1];
        if (!encoded) return false;
        const role = JSON.parse(atob(encoded.replace(/-/g, '+').replace(/_/g, '/'))).role;
        if (role !== 'anon') return false;
      }
      return u.protocol === 'https:' && /^[a-z0-9-]+\.supabase\.co$/i.test(u.hostname) && (u.pathname === '/' || u.pathname === '') && !u.username && !u.password && !u.search && !u.hash;
    } catch (_) { return false; }
  };
  const headers = (withSession = false) => ({
    apikey: state.key,
    ...(withSession ? { Authorization: `Bearer ${state.session.access_token}` } : !state.key.startsWith('sb_publishable_') ? { Authorization: `Bearer ${state.key}` } : {}),
  });
  async function request(path, options = {}) {
    const response = await fetch(state.url + path, options);
    const text = await response.text();
    let body = null;
    try { body = text ? JSON.parse(text) : null; } catch (_) { /* use generic failure */ }
    if (!response.ok) {
      const error = new Error(body?.msg || body?.error_description || body?.message || '요청을 처리하지 못했어요. 다시 시도해 주세요.');
      error.code = body?.error_code || body?.code;
      throw error;
    }
    return body;
  }
  function renderAuth() {
    if (demo) {
      show('config-panel', false); show('auth-panel', false); show('workspace', true); show('logout', false);
      $('account').textContent = '미리보기 전용';
      $('submit-ad').disabled = true;
      $('drafts').textContent = '미리보기에서는 광고가 등록되지 않아요.';
      return;
    }
    show('admin-link', !!state.session && state.admin);
    show('config-panel', !configValid(state.url, state.key));
    show('auth-panel', configValid(state.url, state.key) && !state.session);
    show('workspace', !!state.session);
    if (state.session) $('account').textContent = state.session.user.email || '광고 계정';
  }
  $('config-form').addEventListener('submit', event => {
    event.preventDefault();
    const url = $('project-url').value.trim().replace(/\/$/, '');
    const key = $('public-key').value.trim();
    if (!configValid(url, key)) { message('Supabase 프로젝트 URL과 공개용 키를 확인해 주세요.'); return; }
    state.url = url; state.key = key;
    localStorage.setItem('advertiser-config', JSON.stringify({url, key}));
    renderAuth(); message('연결 정보를 저장했어요.');
  });
  async function authenticate(signup) {
    const email = $('email').value.trim(), password = $('password').value;
    if (!email || password.length < 8 || !$('email').validity.valid) { message('이메일과 8자 이상 비밀번호를 입력해 주세요.'); return; }
    message('처리 중이에요.');
    try {
      const path = signup ? '/auth/v1/signup' : '/auth/v1/token?grant_type=password';
      const result = await request(path, {method: 'POST', headers: {...headers(), 'Content-Type': 'application/json'}, body: JSON.stringify({email, password})});
      $('password').value = '';
      if (!result?.access_token || !result?.user) { show('verify-email', true); message('인증 메일이 도착하면 링크를 눌러 주세요.'); return; }
      state.session = result;
      const stored = window.TripSession.save(result, state.url);
      state.admin = false;
      renderAuth(); message('');
      await Promise.all([checkAdmin(), loadDrafts()]);
      if (!stored) message('브라우저에서 로그인 상태를 저장할 수 없어 화면 이동이 제한될 수 있어요.');
    } catch (error) {
      if (error.code === 'email_not_confirmed') {
        show('verify-email', true);
        message('이메일 인증이 아직 완료되지 않았어요. 인증 메일을 확인해 주세요.');
      } else {
        message('로그인 또는 가입에 실패했어요. 입력 정보와 이메일 확인 여부를 확인해 주세요.');
      }
    }
  }
  async function checkAdmin() {
    if (!state.session) return;
    const token = state.session.access_token;
    try {
      const allowed = await request('/rest/v1/rpc/is_ad_admin', {method: 'POST', headers: {...headers(true), 'Content-Type': 'application/json'}, body: '{}'});
      if (state.session?.access_token === token) { state.admin = allowed === true; renderAuth(); }
    } catch (_) {
      if (state.session?.access_token === token) { state.admin = false; renderAuth(); message('관리자 권한을 확인하지 못했어요. 다시 로그인해 주세요.'); }
    }
  }
  async function restoreSession() {
    if (demo || !configValid(state.url, state.key)) return;
    const saved = window.TripSession.read(state.url);
    if (!saved) return;
    try {
      state.session = saved;
      const user = await request('/auth/v1/user', {headers: headers(true)});
      if (!user?.id) throw new Error('Invalid session');
      state.session.user = user;
      window.TripSession.save(state.session, state.url);
      renderAuth();
      await Promise.all([checkAdmin(), loadDrafts()]);
    } catch (_) {
      state.session = null; state.admin = false; window.TripSession.clear(); renderAuth();
      message('로그인 상태를 확인하지 못했어요. 다시 로그인해 주세요.');
    }
  }
  $('auth-form').addEventListener('submit', event => { event.preventDefault(); authenticate(false); });
  $('signup').addEventListener('click', () => authenticate(true));
  $('resend-email').addEventListener('click', async () => {
    const email = $('email').value.trim();
    if (!email || !$('email').validity.valid) { message('인증할 이메일 주소를 입력해 주세요.'); return; }
    const button = $('resend-email'); button.disabled = true;
    try {
      await request('/auth/v1/resend', {method:'POST', headers:{...headers(), 'Content-Type':'application/json'}, body:JSON.stringify({type:'signup', email})});
      message('인증 메일을 다시 요청했어요. 메일함을 확인해 주세요.');
    } catch (_) {
      message('인증 메일을 보내지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally { button.disabled = false; }
  });
  $('logout').addEventListener('click', async () => {
    const token = state.session?.access_token;
    try { if (token) await request('/auth/v1/logout', {method: 'POST', headers: headers(true)}); } catch (_) { /* local logout still completes */ }
    state.session = null; state.admin = false; window.TripSession.clear(); $('ad-form').reset(); updatePreview(); renderAuth(); message('로그아웃했어요.');
  });
  function updatePreview() {
    $('preview-merchant').textContent = $('merchant').value.trim() || '업체명';
    $('preview-title').textContent = $('title').value.trim() || '상품 제목';
    $('preview-description').textContent = `${$('duration').value || '3'}일 · ${$('description').value.trim() || '한 줄 설명'}`;
    const price = $('price').value;
    $('preview-price').textContent = price ? `등록 가격 ${Number(price).toLocaleString('ko-KR')}원` : '';
  }
  $('ad-form').addEventListener('input', updatePreview);
  $('image').addEventListener('change', () => {
    if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
    state.previewUrl = null;
    const file = $('image').files[0];
    if (file) { state.previewUrl = URL.createObjectURL(file); $('preview-image').src = state.previewUrl; }
    show('preview-image', !!file); show('image-placeholder', !file);
  });
  async function loadDrafts() {
    const list = $('drafts'); list.replaceChildren();
    try {
      const drafts = await request(`/rest/v1/advertiser_drafts?select=id,title,created_at,review_status,review_note&owner_id=eq.${encodeURIComponent(state.session.user.id)}&order=created_at.desc`, {headers: headers(true)});
      if (!drafts.length) { list.textContent = '아직 등록한 광고가 없어요.'; return; }
      for (const draft of drafts) {
        const item = document.createElement('div'); item.className = 'draft';
        const title = document.createElement('strong'); title.textContent = draft.title;
        const note = document.createElement('small'); note.textContent = ({pending:'검토 대기', approved:'승인됨', rejected:'반려됨'})[draft.review_status] || '상태 확인 중'; if (draft.review_status === 'rejected' && draft.review_note) note.textContent += ` · ${draft.review_note}`;
        item.append(title, note); list.append(item);
      }
    } catch (_) { list.textContent = '등록 내역을 불러오지 못했어요.'; }
  }
  $('ad-form').addEventListener('submit', async event => {
    event.preventDefault();
    if (!state.session) return;
    const file = $('image').files[0];
    const purchase = $('purchase').value.trim();
    if (!file || !['image/jpeg','image/png','image/webp'].includes(file.type) || file.size > 3145728) { message('이미지는 3MB 이하의 JPG, PNG, WEBP 파일로 선택해 주세요.'); return; }
    if (!https(purchase)) { message('구매 링크는 https://로 시작해야 해요.'); return; }
    const description = $('description').value.trim();
    if (!description || /[\r\n]/.test(description)) { message('설명은 한 줄로 입력해 주세요.'); return; }
    const extension = {'image/jpeg':'jpg','image/png':'png','image/webp':'webp'}[file.type];
    const objectPath = `${state.session.user.id}/${crypto.randomUUID()}.${extension}`;
    $('submit-ad').disabled = true; message('광고를 등록하고 있어요.');
    try {
      await request(`/storage/v1/object/ad-draft-images/${objectPath}`, {method: 'POST', headers: {...headers(true), 'Content-Type': file.type, 'x-upsert': 'false'}, body: file});
      const body = {
        merchant_name: $('merchant').value.trim(), title: $('title').value.trim(), description,
        sim_type: $('sim-type').value, country_code: $('country').value,
        duration_days: Number($('duration').value), price_krw: $('price').value === '' ? null : Number($('price').value),
        image_path: objectPath, purchase_url: purchase,
      };
      await request('/rest/v1/advertiser_drafts', {method: 'POST', headers: {...headers(true), 'Content-Type': 'application/json', Prefer: 'return=minimal'}, body: JSON.stringify(body)});
      $('ad-form').reset();
      if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
      state.previewUrl = null; $('preview-image').removeAttribute('src'); show('preview-image', false); show('image-placeholder', true); updatePreview();
      message('검토 요청을 보냈어요. 관리자 확인 후 앱에 표시됩니다.'); await loadDrafts();
    } catch (_) {
      message('등록 결과를 확인하지 못했어요. 중복 등록을 피하려면 내 검토 요청을 먼저 확인해 주세요.');
      await loadDrafts();
    } finally { $('submit-ad').disabled = false; }
  });
  try {
    const saved = JSON.parse(localStorage.getItem('advertiser-config') || '{}');
    const config = configValid(saved.url, saved.key) ? saved : window.ADVERTISER_CONFIG || {};
    if (configValid(config.url, config.key)) { state.url = config.url; state.key = config.key; }
  } catch (_) { /* configuration can be entered again */ }
  renderAuth(); updatePreview(); restoreSession();
})();
