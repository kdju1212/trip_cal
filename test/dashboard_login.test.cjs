'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../advertiser');
const source = name => fs.readFileSync(path.join(root, name), 'utf8');
const wait = () => new Promise(resolve => setTimeout(resolve, 10));

function browser(storage, role, loginError = false, fixtures = []) {
  const elements = new Map();
  const responses = [];
  function el(id) {
    if (!elements.has(id)) elements.set(id, {
      id, hidden: true, textContent: '', value: '', disabled: false, files: [], validity: {valid:true},
      listeners: {}, dataset:{}, classList:{toggle(){}},
      addEventListener(event, callback) { this.listeners[event] = callback; },
      replaceChildren(){}, append(){}, removeAttribute(){}, setAttribute(){}, reset(){}, showModal(){this.open=true;}, close(){this.open=false;},
    });
    return elements.get(id);
  }
  const sessionStorage = {getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)};
  const config = {url:'https://example.supabase.co',key:'sb_publishable_test'};
  const context = {
    console, URL, URLSearchParams, Date, JSON, Map, Promise, setTimeout, clearTimeout,
    location:{search:'', assign(value){responses.push({navigation:value});}},
    sessionStorage, localStorage:{getItem(){return null;},setItem(){}},
    document:{getElementById:el,querySelectorAll(){return [];},createElement(){return el('created-'+Math.random());}},
    fetch:async (url, options={})=>{
      const u = new URL(url), token = options.headers?.Authorization;
      responses.push({path:u.pathname, search:u.search, token, method:options.method || 'GET', body:options.body});
      let body;
      if (u.pathname==='/auth/v1/token' && loginError) return {ok:false,status:400,text:async()=>JSON.stringify({error_code:'email_not_confirmed'})};
      if (u.pathname==='/auth/v1/token') body = {access_token:'token',expires_in:3600,user:{id:'user-1',email:'test@example.com'},refresh_token:'never-store'};
      else if (u.pathname==='/auth/v1/signup') body = {user:{id:'user-1',email:'test@example.com'}};
      else if (u.pathname==='/auth/v1/resend') body = {};
      else if(u.pathname==='/auth/v1/user') body = {id:'user-1',email:'test@example.com'};
      else if(u.pathname==='/rest/v1/rpc/is_ad_admin') body = role;
      else if(u.pathname==='/rest/v1/advertiser_drafts') body = fixtures;
      else if(u.pathname==='/rest/v1/sim_ads') body = [];
      else if(u.pathname==='/rest/v1/ad_campaigns' && options.method==='POST') body = [{id:'campaign-1',name:JSON.parse(options.body).name}];
      else if(u.pathname==='/rest/v1/rpc/ad_billing_enabled') body = false;
      else if(u.pathname==='/rest/v1/ad_wallets' || u.pathname==='/rest/v1/rpc/list_advertiser_wallets' || u.pathname==='/rest/v1/ad_campaigns' || u.pathname==='/rest/v1/ad_groups' || u.pathname==='/rest/v1/rpc/my_ad_performance_breakdown' || u.pathname==='/rest/v1/rpc/my_ad_delivery' || u.pathname==='/rest/v1/rpc/my_ad_costs') body = [];
      else if(u.pathname==='/auth/v1/logout') body = {};
      else throw new Error('Unexpected request '+u.pathname);
      return {ok:true,status:200,text:async()=>JSON.stringify(body)};
    },
  };
  context.window = context; context.window.ADVERTISER_CONFIG = config;
  vm.createContext(context);
  vm.runInContext(source('session.js'), context);
  return {context,el,responses};
}

test('한 번 로그인한 관리자는 관리자 화면으로 이동하고 로그아웃한다', async () => {
  const storage = new Map(), login = browser(storage,true);
  vm.runInContext(source('app.js'),login.context);
  login.el('email').value='test@example.com';login.el('password').value='password123';
  await login.el('auth-form').listeners.submit({preventDefault(){}}); await wait();
  assert.equal(login.el('admin-link').hidden,false);
  assert.equal(login.el('workspace').hidden,false);
  assert.equal(login.el('dashboard-view').hidden,false);
  assert.equal(login.el('create-view').hidden,true);
  assert.ok(login.responses.some(x=>x.search.includes('owner_id=eq.user-1')));
  assert.ok(![...storage.values()][0].includes('never-store'));
  const admin = browser(storage,true);
  vm.runInContext(source('admin.js'),admin.context); await wait();
  assert.equal(admin.el('admin-workspace').hidden,false);
  assert.equal(admin.el('admin-login').hidden,true);
  assert.ok(admin.responses.some(x=>x.path==='/auth/v1/user' && x.token==='Bearer token'));
  assert.ok(admin.responses.some(x=>x.path==='/rest/v1/rpc/is_ad_admin'));
  await admin.el('admin-logout').listeners.click();
  assert.equal(storage.size,0);
  assert.ok(admin.responses.some(x=>x.navigation==='index.html'));
});

test('광고주는 로그인 후 대시보드를 보고 소재 작성 화면으로 이동한다', async () => {
  const storage = new Map();
  const fixtures = [
    {id:'1',title:'유심 3일',country_code:'JP',sim_type:'sim',duration_days:3,review_status:'pending'},
    {id:'2',title:'이심 3일',country_code:'JP',sim_type:'esim',duration_days:3,review_status:'approved'},
    {id:'3',title:'수정 필요',country_code:'JP',sim_type:'sim',duration_days:3,review_status:'rejected',review_note:'내용 확인'},
  ];
  const b = browser(storage,false,false,fixtures);
  vm.runInContext(source('app.js'),b.context);
  b.el('email').value='test@example.com'; b.el('password').value='password123';
  await b.el('auth-form').listeners.submit({preventDefault(){}}); await wait();
  assert.equal(b.el('dashboard-view').hidden,false);
  assert.equal(b.el('create-view').hidden,true);
  assert.equal(b.el('stat-total').textContent,'3');
  assert.equal(b.el('stat-pending').textContent,'1');
  assert.equal(b.el('stat-approved').textContent,'1');
  assert.equal(b.el('stat-rejected').textContent,'1');
  b.el('open-create').listeners.click();
  assert.equal(b.el('dashboard-view').hidden,true);
  assert.equal(b.el('create-view').hidden,false);
  b.el('back-dashboard').listeners.click();
  assert.equal(b.el('dashboard-view').hidden,false);
  assert.equal(b.el('create-view').hidden,true);
});

test('일반 광고주는 관리자 메뉴를 볼 수 없고 직접 열어도 거절된다', async () => {
  const storage = new Map(), login = browser(storage,false);
  vm.runInContext(source('app.js'),login.context);
  login.el('email').value='test@example.com';login.el('password').value='password123';
  await login.el('auth-form').listeners.submit({preventDefault(){}}); await wait();
  assert.equal(login.el('admin-link').hidden,true);
  const admin = browser(storage,false);
  vm.runInContext(source('admin.js'),admin.context); await wait();
  assert.equal(admin.el('admin-workspace').hidden,true);
  assert.equal(admin.el('admin-login-title').textContent,'관리자 권한이 없어요');
  assert.ok(!admin.responses.some(x=>x.path==='/rest/v1/advertiser_drafts'));
});

test('만료된 세션은 재사용하지 않는다', () => {
  const storage = new Map(), b = browser(storage,true);
  storage.set('trip-cal-dashboard-session-v1', JSON.stringify({projectUrl:'https://example.supabase.co',access_token:'old',expires_at:1,user:{id:'user-1'}}));
  assert.equal(b.context.TripSession.read('https://example.supabase.co'),null);
  assert.equal(storage.size,0);
});

test('가입 후 이메일 확인 안내와 인증 메일 재전송이 가능하다', async () => {
  const storage = new Map(), login = browser(storage,false);
  vm.runInContext(source('app.js'),login.context);
  login.el('email').value='test@example.com'; login.el('password').value='password123';
  await login.el('signup').listeners.click();
  assert.equal(login.el('verify-email').hidden,false);
  assert.equal(login.el('workspace').hidden,true);
  assert.equal(storage.size,0);
  await login.el('resend-email').listeners.click();
  assert.ok(login.responses.some(x=>x.path==='/auth/v1/resend'));
  assert.match(login.el('message').textContent,/다시 요청/);
});

test('이메일 미인증 로그인은 인증 안내를 보여주고 세션을 만들지 않는다', async () => {
  const storage = new Map(), login = browser(storage,false,true);
  vm.runInContext(source('app.js'),login.context);
  login.el('email').value='test@example.com'; login.el('password').value='password123';
  await login.el('auth-form').listeners.submit({preventDefault(){}}); await wait();
  assert.equal(login.el('verify-email').hidden,false);
  assert.equal(login.el('workspace').hidden,true);
  assert.equal(storage.size,0);
  assert.match(login.el('message').textContent,/인증이 아직 완료되지/);
});

test('소재 없이 새 캠페인을 따로 만들 수 있다', async () => {
  const storage = new Map(), b = browser(storage,false);
  vm.runInContext(source('app.js'),b.context);
  b.el('email').value='test@example.com'; b.el('password').value='password123';
  await b.el('auth-form').listeners.submit({preventDefault(){}}); await wait();
  b.el('new-campaign-button').listeners.click();
  assert.equal(b.el('edit-dialog').open,true);
  b.el('edit-name').value='여름 여행'; b.el('edit-budget').value='10000';
  await b.el('edit-form').listeners.submit({preventDefault(){}});
  const created=b.responses.find(x=>x.path==='/rest/v1/ad_campaigns' && x.method==='POST');
  assert.deepEqual(JSON.parse(created.body),{name:'여름 여행',daily_budget_krw:10000});
  assert.ok(!b.responses.some(x=>x.path==='/rest/v1/advertiser_drafts' && x.method==='POST'));
});
