'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const state = { url: '', key: '', session: null, admin: false, previewUrl: null, view: 'dashboard', campaigns: [], groups: [], performance: null, performanceView: 'campaign' };
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
      show('dashboard-view', state.view === 'dashboard'); show('create-view', state.view === 'create');
      return;
    }
    show('admin-link', !!state.session && state.admin);
    show('config-panel', !configValid(state.url, state.key));
    show('auth-panel', configValid(state.url, state.key) && !state.session);
    show('workspace', !!state.session);
    show('dashboard-view', !!state.session && state.view === 'dashboard');
    show('create-view', !!state.session && state.view === 'create');
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
      await Promise.all([checkAdmin(), loadDrafts(), loadPerformance()]);
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
      await Promise.all([checkAdmin(), loadDrafts(), loadPerformance()]);
    } catch (_) {
      state.session = null; state.admin = false; state.view = 'dashboard'; window.TripSession.clear(); renderAuth();
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
    state.session = null; state.admin = false; state.view = 'dashboard'; state.campaigns = []; state.groups = []; state.performance = null; window.TripSession.clear(); $('ad-form').reset(); $('image').setCustomValidity('');
    if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
    state.previewUrl = null; $('preview-image').removeAttribute('src'); show('preview-image', false); show('image-placeholder', true);
    updatePreview(); renderAuth(); message('로그아웃했어요.');
  });
  function setView(view) {
    if (!state.session && !demo) return;
    state.view = view;
    renderAuth();
    if (typeof window.scrollTo === 'function') window.scrollTo(0, 0);
  }
  $('open-create').addEventListener('click', async () => { setView('create'); if (state.session) await loadHierarchy(); });
  $('back-dashboard').addEventListener('click', () => setView('dashboard'));
  $('refresh-drafts').addEventListener('click', () => { if (state.session) loadDrafts(); });
  function fillOptions(id, items, placeholder) {
    const select = $(id), previous = select.value;
    select.replaceChildren();
    const first = document.createElement('option'); first.value = ''; first.textContent = placeholder; select.append(first);
    for (const item of items) { const option = document.createElement('option'); option.value = item.id; option.textContent = item.name; select.append(option); }
    if (items.some(item => item.id === previous)) select.value = previous;
  }
  function updateGroupSelection() {
    const group = state.groups.find(g => g.id === $('group-select').value);
    show('new-group', !group);
    for (const id of ['sim-type', 'country', 'duration']) $(id).disabled = !!group;
    if (group) { $('sim-type').value = group.sim_type; $('country').value = group.country_code; $('duration').value = group.duration_days; }
    updatePreview();
  }
  function updateCampaignSelection() {
    const campaign = $('campaign-select').value;
    show('new-campaign', !campaign);
    fillOptions('group-select', state.groups.filter(g => g.campaign_id === campaign), '새 광고그룹 만들기');
    updateGroupSelection();
  }
  $('campaign-select').addEventListener('change', updateCampaignSelection);
  $('group-select').addEventListener('change', updateGroupSelection);
  async function loadHierarchy() {
    try {
      const [campaigns, groups] = await Promise.all([
        request(`/rest/v1/ad_campaigns?select=id,name,daily_budget_krw&owner_id=eq.${encodeURIComponent(state.session.user.id)}&order=created_at.desc`, {headers: headers(true)}),
        request(`/rest/v1/ad_groups?select=id,campaign_id,name,sim_type,country_code,duration_days,cpc_bid_krw&owner_id=eq.${encodeURIComponent(state.session.user.id)}&order=created_at.desc`, {headers: headers(true)})
      ]);
      state.campaigns = campaigns; state.groups = groups;
      fillOptions('campaign-select', campaigns, '새 캠페인 만들기'); updateCampaignSelection();
    } catch (_) { message('캠페인 정보를 불러오지 못했어요. 다시 시도해 주세요.'); }
  }
  async function createRecord(table, payload) {
    const records = await request('/rest/v1/' + table, {method:'POST', headers:{...headers(true), 'Content-Type':'application/json', Prefer:'return=representation'}, body:JSON.stringify(payload)});
    if (!Array.isArray(records) || !records[0]?.id) throw new Error('저장 결과를 확인하지 못했어요.');
    return records[0];
  }
  async function loadPerformance() {
    if (!state.session) return;
    const list = $('performance-list'); list.textContent = '성과를 불러오고 있어요.';
    const owner = encodeURIComponent(state.session.user.id);
    try {
      const [campaigns, groups, drafts, metrics] = await Promise.all([
        request(`/rest/v1/ad_campaigns?select=id,name&owner_id=eq.${owner}&order=created_at.desc`, {headers:headers(true)}),
        request(`/rest/v1/ad_groups?select=id,campaign_id,name&owner_id=eq.${owner}&order=created_at.desc`, {headers:headers(true)}),
        request(`/rest/v1/advertiser_drafts?select=id,group_id,title,review_status&owner_id=eq.${owner}&order=created_at.desc`, {headers:headers(true)}),
        request('/rest/v1/rpc/my_ad_performance', {method:'POST',headers:{...headers(true),'Content-Type':'application/json'},body:'{}'})
      ]);
      if (![campaigns, groups, drafts, metrics].every(Array.isArray)) throw new Error('Invalid response');
      state.performance = {campaigns, groups, drafts, metrics}; renderPerformance();
    } catch (_) { state.performance = null; list.textContent = '성과를 불러오지 못했어요. 새로고침을 눌러 주세요.'; }
  }
  function renderPerformance() {
    const list = $('performance-list'), data = state.performance;
    if (!data) return;
    list.replaceChildren();
    const metrics = new Map(data.metrics.map(m => [m.draft_id, m]));
    const groups = new Map(data.groups.map(g => [g.id,g]));
    const campaignNames = new Map(data.campaigns.map(c => [c.id,c.name]));
    let rows;
    if (state.performanceView === 'creative') rows = data.drafts.map(d => ({name:d.title, detail:groups.get(d.group_id)?.name || '기존 소재', drafts:[d]}));
    else if (state.performanceView === 'group') rows = data.groups.map(g => ({name:g.name, detail:campaignNames.get(g.campaign_id) || '', drafts:data.drafts.filter(d => d.group_id === g.id)}));
    else rows = data.campaigns.map(c => ({name:c.name, detail:'캠페인 전체 합계', drafts:data.drafts.filter(d => groups.get(d.group_id)?.campaign_id === c.id)}));
    if (!rows.length) { list.textContent = '아직 등록된 항목이 없어요.'; return; }
    for (const item of rows) {
      let loaded = 0, clicks = 0;
      for (const draft of item.drafts) { const m = metrics.get(draft.id); loaded += Number(m?.loaded || 0); clicks += Number(m?.clicks || 0); }
      const row = document.createElement('div'); row.className = 'performance-row';
      const label = document.createElement('div'), title = document.createElement('strong'), detail = document.createElement('small');
      title.textContent = item.name; detail.textContent = item.detail; label.append(title,detail);
      const values = document.createElement('div'); values.className = 'performance-values'; values.textContent = `목록 불러옴 ${loaded.toLocaleString('ko-KR')} · 클릭 ${clicks.toLocaleString('ko-KR')}`;
      row.append(label,values); list.append(row);
    }
  }
  document.querySelectorAll('[data-performance]').forEach(button => button.addEventListener('click', () => {
    state.performanceView = button.dataset.performance;
    document.querySelectorAll('[data-performance]').forEach(b => b.classList.toggle('active', b === button));
    renderPerformance();
  }));
  $('refresh-performance').addEventListener('click', loadPerformance);
  function updatePreview() {
    $('preview-merchant').textContent = $('merchant').value.trim() || '업체명';
    $('preview-title').textContent = $('title').value.trim() || '상품 제목';
    $('preview-description').textContent = `${$('duration').value || '3'}일 · ${$('description').value.trim() || '한 줄 설명'}`;
    const price = $('price').value;
    $('preview-price').textContent = price ? `가격 ${Number(price).toLocaleString('ko-KR')}원` : '';
  }
  $('ad-form').addEventListener('input', updatePreview);
  $('image').addEventListener('change', async () => {
    const input = $('image'), file = input.files[0];
    input.setCustomValidity('');
    if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
    state.previewUrl = null;
    $('preview-image').removeAttribute('src'); show('preview-image', false); show('image-placeholder', true);
    if (!file) return;
    const square = await window.TripImageRatio.isSquare(file);
    if (input.files[0] !== file) return;
    if (!square) {
      input.setCustomValidity('이미지는 가로와 세로가 같은 1:1 정사각형으로 선택해 주세요.');
      message('이미지는 가로와 세로가 같은 1:1 정사각형으로 선택해 주세요.');
      return;
    }
    state.previewUrl = URL.createObjectURL(file); $('preview-image').src = state.previewUrl;
    show('preview-image', true); show('image-placeholder', false);
  });
  async function loadDrafts() {
    const list = $('drafts');
    list.className = ''; list.textContent = '광고 현황을 불러오고 있어요.';
    for (const id of ['stat-total', 'stat-pending', 'stat-approved', 'stat-rejected']) $(id).textContent = '—';
    try {
      const drafts = await request(`/rest/v1/advertiser_drafts?select=id,title,created_at,sim_type,country_code,duration_days,review_status,review_note&owner_id=eq.${encodeURIComponent(state.session.user.id)}&order=created_at.desc&limit=100`, {headers: headers(true)});
      if (!Array.isArray(drafts)) throw new Error('Invalid response');
      $('stat-total').textContent = String(drafts.length);
      $('stat-pending').textContent = String(drafts.filter(d => d.review_status === 'pending').length);
      $('stat-approved').textContent = String(drafts.filter(d => d.review_status === 'approved').length);
      $('stat-rejected').textContent = String(drafts.filter(d => d.review_status === 'rejected').length);
      list.replaceChildren();
      if (!drafts.length) {
        const empty = document.createElement('div'); empty.className = 'empty-dashboard';
        const title = document.createElement('strong'); title.textContent = '아직 등록한 광고가 없어요';
        const detail = document.createElement('p'); detail.textContent = '소재를 만들면 이곳에서 검토 상태를 확인할 수 있어요.';
        empty.append(title, detail); list.append(empty); return;
      }
      for (const draft of drafts) {
        const row = document.createElement('div'); row.className = 'draft-row';
        const content = document.createElement('div'); content.className = 'draft-content';
        const title = document.createElement('strong'); title.textContent = draft.title;
        const detail = document.createElement('small');
        detail.textContent = [draft.country_code, draft.sim_type === 'esim' ? 'eSIM' : '유심', draft.duration_days == null ? '' : `${draft.duration_days}일`].filter(Boolean).join(' · ');
        content.append(title, detail);
        if (draft.review_status === 'rejected' && draft.review_note) {
          const note = document.createElement('small'); note.textContent = `반려 사유: ${draft.review_note}`; content.append(note);
        }
        const status = document.createElement('span'); status.className = `status ${['approved','rejected'].includes(draft.review_status) ? draft.review_status : ''}`;
        status.textContent = ({pending:'검토 대기', approved:'승인', rejected:'반려'})[draft.review_status] || '상태 확인 중';
        row.append(content, status); list.append(row);
      }
    } catch (_) { list.replaceChildren(); list.textContent = '광고 현황을 불러오지 못했어요. 새로고침을 눌러 주세요.'; list.className = 'dashboard-error'; }
  }
  $('ad-form').addEventListener('submit', async event => {
    event.preventDefault();
    if (!state.session) return;
    if (!$('campaign-select').value && !$('campaign-name').value.trim()) { message('캠페인 이름을 입력해 주세요.'); return; }
    if (!$('group-select').value && (!$('group-name').value.trim() || $('group-bid').value === '')) { message('광고그룹 이름과 클릭당 입찰가를 입력해 주세요.'); return; }
    const file = $('image').files[0];
    const purchase = $('purchase').value.trim();
    if (!file || !['image/jpeg','image/png','image/webp'].includes(file.type) || file.size > 3145728) { message('이미지는 3MB 이하의 JPG, PNG, WEBP 파일로 선택해 주세요.'); return; }
    if (!https(purchase)) { message('구매 링크는 https://로 시작해야 해요.'); return; }
    const description = $('description').value.trim();
    if (!description || /[\r\n]/.test(description)) { message('설명은 한 줄로 입력해 주세요.'); return; }
    if ($('submit-ad').disabled) return;
    $('submit-ad').disabled = true;
    const square = await window.TripImageRatio.isSquare(file);
    if (!square || $('image').files[0] !== file) {
      $('submit-ad').disabled = false;
      message('이미지는 가로와 세로가 같은 1:1 정사각형으로 선택해 주세요.');
      return;
    }
    const extension = {'image/jpeg':'jpg','image/png':'png','image/webp':'webp'}[file.type];
    const objectPath = `${state.session.user.id}/${crypto.randomUUID()}.${extension}`;
    $('submit-ad').disabled = true; message('광고를 등록하고 있어요.');
    try {
      let campaign = state.campaigns.find(c => c.id === $('campaign-select').value);
      if (!campaign) {
        campaign = await createRecord('ad_campaigns', {name:$('campaign-name').value.trim(), daily_budget_krw:$('campaign-budget').value === '' ? null : Number($('campaign-budget').value)});
        state.campaigns.unshift(campaign); fillOptions('campaign-select', state.campaigns, '새 캠페인 만들기'); $('campaign-select').value = campaign.id; updateCampaignSelection();
      }
      let group = state.groups.find(g => g.id === $('group-select').value);
      if (!group) {
        group = await createRecord('ad_groups', {campaign_id:campaign.id, name:$('group-name').value.trim(), sim_type:$('sim-type').value, country_code:$('country').value, duration_days:Number($('duration').value), cpc_bid_krw:Number($('group-bid').value)});
        state.groups.unshift(group); updateCampaignSelection(); $('group-select').value = group.id; updateGroupSelection();
      }
      await request(`/storage/v1/object/ad-draft-images/${objectPath}`, {method: 'POST', headers: {...headers(true), 'Content-Type': file.type, 'x-upsert': 'false'}, body: file});
      const body = {
        group_id: group.id, merchant_name: $('merchant').value.trim(), title: $('title').value.trim(), description,
        sim_type: $('sim-type').value, country_code: $('country').value,
        duration_days: Number($('duration').value), price_krw: $('price').value === '' ? null : Number($('price').value),
        image_path: objectPath, purchase_url: purchase,
      };
      await request('/rest/v1/advertiser_drafts', {method: 'POST', headers: {...headers(true), 'Content-Type': 'application/json', Prefer: 'return=minimal'}, body: JSON.stringify(body)});
      $('ad-form').reset(); $('image').setCustomValidity(''); updateCampaignSelection();
      if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
      state.previewUrl = null; $('preview-image').removeAttribute('src'); show('preview-image', false); show('image-placeholder', true); updatePreview();
      setView('dashboard'); message('검토 요청을 보냈어요. 관리자 확인 후 앱에 표시됩니다.'); await Promise.all([loadDrafts(), loadPerformance()]);
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
