'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const state = { url: '', key: '', session: null, admin: false, previewUrl: null, view: 'dashboard', campaigns: [], groups: [], performance: null, performanceView: 'campaign', performanceCampaign: null, performanceGroup: null, performanceRequest: 0 };
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
        request(`/rest/v1/ad_campaigns?select=id,name,daily_budget_krw,advertiser_enabled&deleted_at=is.null&owner_id=eq.${encodeURIComponent(state.session.user.id)}&order=created_at.desc`, {headers: headers(true)}),
        request(`/rest/v1/ad_groups?select=id,campaign_id,name,sim_type,country_code,duration_days,cpc_bid_krw,advertiser_enabled&deleted_at=is.null&owner_id=eq.${encodeURIComponent(state.session.user.id)}&order=created_at.desc`, {headers: headers(true)})
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
    const requestId = ++state.performanceRequest;
    const list = $('performance-list'); list.textContent = '성과를 불러오고 있어요.';
    $('performance-loaded').textContent = '—'; $('performance-clicks').textContent = '—'; $('performance-candidate').textContent = '—'; $('performance-excluded').textContent = '—';
    const owner = encodeURIComponent(state.session.user.id);
    try {
      const [campaigns, groups, drafts, metrics, delivery] = await Promise.all([
        request(`/rest/v1/ad_campaigns?select=id,name,daily_budget_krw,advertiser_enabled&deleted_at=is.null&owner_id=eq.${owner}&order=created_at.desc`, {headers:headers(true)}),
        request(`/rest/v1/ad_groups?select=id,campaign_id,name,sim_type,country_code,duration_days,cpc_bid_krw,advertiser_enabled&deleted_at=is.null&owner_id=eq.${owner}&order=created_at.desc`, {headers:headers(true)}),
        request(`/rest/v1/advertiser_drafts?select=id,group_id,title,merchant_name,description,price_krw,purchase_url,review_status,advertiser_enabled&deleted_at=is.null&owner_id=eq.${owner}&order=created_at.desc`, {headers:headers(true)}),
        request('/rest/v1/rpc/my_ad_performance_breakdown', {method:'POST',headers:{...headers(true),'Content-Type':'application/json'},body:JSON.stringify({p_days:Number($('performance-period').value || 30)})}),
        request('/rest/v1/rpc/my_ad_delivery', {method:'POST',headers:{...headers(true),'Content-Type':'application/json'},body:'{}'})
      ]);
      if (requestId !== state.performanceRequest || !state.session) return;
      if (![campaigns, groups, drafts, metrics, delivery].every(Array.isArray)) throw new Error('Invalid response');
      state.performance = {campaigns, groups, drafts, metrics, delivery}; renderPerformance();
    } catch (_) {
      if (requestId !== state.performanceRequest) return;
      state.performance = null; list.textContent = '성과를 불러오지 못했어요. 새로고침을 눌러 주세요.';
    }
  }
  function renderPerformance() {
    const list = $('performance-list'), data = state.performance;
    if (!data) return;
    list.replaceChildren();
    const metrics = new Map(data.metrics.map(m => [m.draft_id, m]));
    const groups = new Map(data.groups.map(g => [g.id,g]));
    const campaignNames = new Map(data.campaigns.map(c => [c.id,c.name]));
    const campaigns = new Map(data.campaigns.map(c => [c.id,c]));
    const delivery = new Map(data.delivery.map(d => [d.draft_id,d.admin_active]));
    const visibleDrafts = data.drafts.filter(d => (!state.performanceCampaign || groups.get(d.group_id)?.campaign_id === state.performanceCampaign) && (!state.performanceGroup || d.group_id === state.performanceGroup));
    const sums = drafts => drafts.reduce((total,d) => { const m=metrics.get(d.id); total.loaded+=Number(m?.loaded || 0); total.clicks+=Number(m?.clicks || 0); total.candidate+=Number(m?.candidate || 0); total.excluded+=Number(m?.excluded || 0); total.unverified+=Number(m?.unverified || 0); return total; }, {loaded:0,clicks:0,candidate:0,excluded:0,unverified:0});
    const total = sums(visibleDrafts);
    $('performance-loaded').textContent = total.loaded.toLocaleString('ko-KR');
    $('performance-clicks').textContent = total.clicks.toLocaleString('ko-KR');
    $('performance-candidate').textContent = total.candidate.toLocaleString('ko-KR');
    $('performance-excluded').textContent = total.excluded.toLocaleString('ko-KR');
    $('performance-context').textContent = [state.performanceCampaign ? campaignNames.get(state.performanceCampaign) : '전체 캠페인', state.performanceGroup ? groups.get(state.performanceGroup)?.name : null].filter(Boolean).join('  ›  ');
    show('clear-performance-filter', !!state.performanceCampaign || !!state.performanceGroup);
    let rows;
    if (state.performanceView === 'creative') rows = visibleDrafts.map(d => ({editId:d.id, name:d.title, detail:groups.get(d.group_id)?.name || '기존 소재', enabled:d.advertiser_enabled !== false, status:d.advertiser_enabled === false ? '소재 꺼짐' : (groups.get(d.group_id)?.advertiser_enabled === false || campaigns.get(groups.get(d.group_id)?.campaign_id)?.advertiser_enabled === false) ? '상위 꺼짐' : d.review_status === 'approved' ? (delivery.get(d.id) ? '노출 중' : '관리자 중지 또는 노출 대기') : ({pending:'검토 대기',rejected:'반려'})[d.review_status] || '확인 중', drafts:[d]}));
    else if (state.performanceView === 'group') rows = data.groups.filter(g => !state.performanceCampaign || g.campaign_id === state.performanceCampaign).map(g => ({id:g.id, enabled:g.advertiser_enabled !== false, status:g.advertiser_enabled === false ? '꺼짐' : campaigns.get(g.campaign_id)?.advertiser_enabled === false ? '상위 꺼짐' : '켜짐', name:g.name, detail:campaignNames.get(g.campaign_id) || '', drafts:visibleDrafts.filter(d => d.group_id === g.id)}));
    else rows = data.campaigns.filter(c => !state.performanceCampaign || c.id === state.performanceCampaign).map(c => ({id:c.id, enabled:c.advertiser_enabled !== false, status:c.advertiser_enabled === false ? '꺼짐' : '켜짐', name:c.name, detail:'광고그룹 보기', drafts:visibleDrafts.filter(d => groups.get(d.group_id)?.campaign_id === c.id)}));
    if (!rows.length) { list.textContent = '표시할 항목이 없어요. 광고를 등록하면 여기에 표시됩니다.'; return; }
    const table=document.createElement('table'); table.className='performance-table';
    const caption=document.createElement('caption'); caption.textContent='광고 성과 비교'; table.append(caption);
    const thead=document.createElement('thead'), header=document.createElement('tr');
    for (const label of [({campaign:'캠페인',group:'광고그룹',creative:'소재'})[state.performanceView], '상태', '노출수', '클릭수', '유효 후보', '자동 제외', '미검증', '관리']) { const th=document.createElement('th'); th.scope='col'; th.textContent=label; header.append(th); }
    thead.append(header); table.append(thead);
    const body=document.createElement('tbody');
    for (const item of rows) {
      const row=document.createElement('tr'), nameCell=document.createElement('td'), label=document.createElement(item.id ? 'button' : 'strong');
      label.textContent=item.name;
      if (item.id) {
        label.type='button'; label.className='performance-name';
        label.addEventListener('click', () => {
          if (state.performanceView === 'campaign') { state.performanceCampaign=item.id; state.performanceGroup=null; setPerformanceView('group'); }
          else { state.performanceGroup=item.id; state.performanceCampaign=groups.get(item.id)?.campaign_id || null; setPerformanceView('creative'); }
        });
      }
      const detail=document.createElement('small'); detail.textContent=item.detail; nameCell.append(label,detail); row.append(nameCell);
      const kind=state.performanceView, editId=item.editId || item.id;
      const stateCell=document.createElement('td'); stateCell.className='delivery-state';
      const switchWrap=document.createElement('span'); switchWrap.className='delivery-switch-wrap';
      const toggle=document.createElement('button'); toggle.type='button'; toggle.className='delivery-switch';
      toggle.setAttribute('role', 'switch'); toggle.setAttribute('aria-label', `${item.name} 광고 설정`); toggle.setAttribute('aria-checked', String(item.enabled));
      const switchLabel=document.createElement('span'); switchLabel.className='delivery-switch-label'; switchLabel.textContent=item.enabled ? '켜짐' : '꺼짐';
      toggle.addEventListener('click', () => changeDelivery(kind,editId,!item.enabled,toggle)); switchWrap.append(toggle,switchLabel); stateCell.append(switchWrap);
      if (item.status && item.status !== switchLabel.textContent) { const detail=document.createElement('small'); detail.textContent=item.status; stateCell.append(detail); }
      row.append(stateCell);
      const m=sums(item.drafts);
      for (const value of [m.loaded.toLocaleString('ko-KR'),m.clicks.toLocaleString('ko-KR'),m.candidate.toLocaleString('ko-KR'),m.excluded.toLocaleString('ko-KR'),m.unverified.toLocaleString('ko-KR')]) { const cell=document.createElement('td'); cell.textContent=value; row.append(cell); }
      const action=document.createElement('td'), edit=document.createElement('button');
      edit.type='button'; edit.className='link'; edit.textContent='수정';
      edit.addEventListener('click', () => openEditor(kind, editId)); action.append(edit);
      const remove=document.createElement('button'); remove.type='button'; remove.className='link delete-action'; remove.textContent='삭제';
      remove.setAttribute('aria-label', `${item.name} 삭제`);
      remove.addEventListener('click', () => deleteItem(kind,editId,item.name,remove)); action.append(remove); row.append(action);
      body.append(row);
    }
    table.append(body); const wrapper=document.createElement('div'); wrapper.className='performance-table-wrap'; wrapper.append(table); list.append(wrapper);
  }
  async function changeDelivery(kind,id,enabled,button) {
    if (!state.session || button.disabled) return;
    button.disabled=true; message('광고 상태를 변경하고 있어요.');
    try {
      await request('/rest/v1/rpc/set_advertiser_delivery', {method:'POST',headers:{...headers(true),'Content-Type':'application/json'},body:JSON.stringify({p_kind:kind,p_id:id,p_enabled:enabled})});
      message(enabled ? '켜기 설정을 저장했어요. 상위 항목과 검수 상태에 따라 실제 노출이 결정됩니다.' : '광고를 껐어요. 해당 항목 아래의 광고도 노출되지 않습니다.');
      await loadPerformance();
    } catch (_) { message('상태를 변경하지 못했어요. 다시 시도해 주세요.'); }
    finally { button.disabled=false; }
  }
  async function deleteItem(kind,id,name,button) {
    if (!state.session || button.disabled) return;
    const nested=kind === 'campaign' ? '아래 광고그룹과 소재도 함께 삭제됩니다.' : kind === 'group' ? '아래 소재도 함께 삭제됩니다.' : '광고 노출이 중지됩니다.';
    if (!window.confirm(`“${name}” 항목을 삭제할까요?\n${nested}\n삭제하면 목록에서 사라지며 화면에서 복구할 수 없습니다. 성과 기록과 검수 이력은 보관됩니다.`)) return;
    button.disabled=true; message('삭제하고 있어요.');
    try {
      await request('/rest/v1/rpc/delete_advertiser_item', {method:'POST',headers:{...headers(true),'Content-Type':'application/json'},body:JSON.stringify({p_kind:kind,p_id:id})});
      if (kind === 'campaign') { state.performanceCampaign=null; state.performanceGroup=null; }
      if (kind === 'group') state.performanceGroup=null;
      message('삭제했어요. 노출은 중지되고 성과 기록과 검수 이력은 보관됩니다.');
      await Promise.all([loadPerformance(),loadDrafts()]);
    } catch (_) { message('삭제하지 못했어요. 다시 시도해 주세요.'); }
    finally { button.disabled=false; }
  }
  function setPerformanceView(view) {
    state.performanceView=view;
    if (view === 'campaign') { state.performanceCampaign=null; state.performanceGroup=null; }
    if (view === 'group') state.performanceGroup=null;
    document.querySelectorAll('[data-performance]').forEach(b => b.classList.toggle('active', b.dataset.performance === view));
    renderPerformance();
  }
  document.querySelectorAll('[data-performance]').forEach(button => button.addEventListener('click', () => setPerformanceView(button.dataset.performance)));
  $('clear-performance-filter').addEventListener('click', () => { state.performanceCampaign=null; state.performanceGroup=null; renderPerformance(); });
  $('performance-period').addEventListener('change', loadPerformance);
  $('refresh-performance').addEventListener('click', loadPerformance);
  let editor = null;
  function openEditor(kind, id) {
    const data=state.performance;
    const item=kind === 'campaign' ? data.campaigns.find(x=>x.id===id) : kind === 'group' ? data.groups.find(x=>x.id===id) : data.drafts.find(x=>x.id===id);
    if (!item) return;
    editor={kind,id}; $('edit-form').reset(); $('edit-message').textContent='';
    $('edit-title').textContent=({campaign:'캠페인 수정',group:'광고그룹 수정',creative:'소재 수정'})[kind];
    $('edit-help').textContent=kind === 'creative' ? '수정하면 다시 검수합니다. 이미 노출 중인 광고는 승인될 때까지 일시 중지됩니다.' : '변경한 설정을 저장해 주세요.';
    show('edit-basic',kind !== 'creative'); show('edit-campaign-fields',kind === 'campaign'); show('edit-group-fields',kind === 'group'); show('edit-creative-fields',kind === 'creative');
    for (const id of ['edit-name','edit-budget','edit-bid','edit-sim','edit-country','edit-duration','edit-merchant','edit-creative-title','edit-description','edit-price','edit-url','edit-image']) {
      const field=$(id); const enabled= id === 'edit-name' ? kind !== 'creative' : id === 'edit-budget' ? kind === 'campaign' : ['edit-bid','edit-sim','edit-country','edit-duration'].includes(id) ? kind === 'group' : kind === 'creative';
      field.disabled=!enabled; field.required=enabled && ['edit-name','edit-bid','edit-duration','edit-merchant','edit-creative-title','edit-description','edit-url'].includes(id);
    }
    if (kind === 'campaign') { $('edit-name').value=item.name; $('edit-budget').value=item.daily_budget_krw ?? ''; }
    if (kind === 'group') {
      $('edit-name').value=item.name; $('edit-bid').value=item.cpc_bid_krw; $('edit-sim').value=item.sim_type;
      $('edit-country').replaceChildren(...Array.from($('country').options, option => option.cloneNode(true)));
      $('edit-country').value=item.country_code; $('edit-duration').value=item.duration_days;
    }
    if (kind === 'creative') { $('edit-merchant').value=item.merchant_name; $('edit-creative-title').value=item.title; $('edit-description').value=item.description; $('edit-price').value=item.price_krw ?? ''; $('edit-url').value=item.purchase_url; }
    $('edit-dialog').showModal();
  }
  $('edit-close').addEventListener('click', () => $('edit-dialog').close());
  $('edit-cancel').addEventListener('click', () => $('edit-dialog').close());
  $('edit-form').addEventListener('submit', async event => {
    event.preventDefault();
    if (!editor || !state.session || $('edit-save').disabled) return;
    const current={...editor}, button=$('edit-save'); button.disabled=true; $('edit-message').textContent='저장 중이에요.';
    try {
      if (current.kind === 'creative') {
        const merchant=$('edit-merchant').value.trim(), title=$('edit-creative-title').value.trim(), description=$('edit-description').value.trim(), url=$('edit-url').value.trim();
        if (!merchant || !title || !description || /[\r\n]/.test(description) || !https(url)) throw new Error('업체명, 제목, 한 줄 설명과 https 구매 링크를 확인해 주세요.');
        let path=null; const file=$('edit-image').files[0];
        if (file) {
          if (!['image/jpeg','image/png','image/webp'].includes(file.type) || file.size>3145728 || !(await window.TripImageRatio.isSquare(file))) throw new Error('이미지는 3MB 이하의 1:1 JPG, PNG, WEBP 파일로 선택해 주세요.');
          const ext={'image/jpeg':'jpg','image/png':'png','image/webp':'webp'}[file.type]; path=`${state.session.user.id}/${crypto.randomUUID()}.${ext}`;
          await request(`/storage/v1/object/ad-draft-images/${path}`, {method:'POST',headers:{...headers(true),'Content-Type':file.type,'x-upsert':'false'},body:file});
        }
        await request('/rest/v1/rpc/edit_ad_creative', {method:'POST',headers:{...headers(true),'Content-Type':'application/json'},body:JSON.stringify({p_id:current.id,p_merchant:merchant,p_title:title,p_description:description,p_price:$('edit-price').value === '' ? null : Number($('edit-price').value),p_url:url,p_image_path:path})});
      } else {
        const name=$('edit-name').value.trim(); if (!name) throw new Error('이름을 입력해 주세요.');
        const campaign=current.kind==='campaign';
        const payload=campaign ? {name,daily_budget_krw:$('edit-budget').value === '' ? null : Number($('edit-budget').value)} : {name,cpc_bid_krw:Number($('edit-bid').value),sim_type:$('edit-sim').value,country_code:$('edit-country').value,duration_days:Number($('edit-duration').value)};
        const table=campaign?'ad_campaigns':'ad_groups';
        const result=await request(`/rest/v1/${table}?id=eq.${encodeURIComponent(current.id)}&owner_id=eq.${encodeURIComponent(state.session.user.id)}&select=id`,{method:'PATCH',headers:{...headers(true),'Content-Type':'application/json',Prefer:'return=representation'},body:JSON.stringify(payload)});
        if (!Array.isArray(result) || result.length!==1) throw new Error('저장할 항목을 찾을 수 없어요. 새로고침해 주세요.');
      }
      $('edit-dialog').close(); message(current.kind === 'creative' ? '소재를 수정하고 다시 검토 요청했어요.' : '변경 사항을 저장했어요.'); await Promise.all([loadPerformance(),loadDrafts()]);
    } catch (error) { $('edit-message').textContent=error.message || '저장하지 못했어요. 다시 시도해 주세요.'; }
    finally { button.disabled=false; }
  });
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
      const drafts = await request(`/rest/v1/advertiser_drafts?select=id,title,created_at,sim_type,country_code,duration_days,review_status,review_note&deleted_at=is.null&owner_id=eq.${encodeURIComponent(state.session.user.id)}&order=created_at.desc&limit=100`, {headers: headers(true)});
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
