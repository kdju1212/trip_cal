// Independent Postgres instance only. Set FINANCE_TEST_PG_MODULE and
// FINANCE_TEST_SOCKET to opt in; never point this test at a production database.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';

test('concurrent partial refunds serialize and never exceed the original debit',
  {skip: !process.env.FINANCE_TEST_PG_MODULE || !process.env.FINANCE_TEST_SOCKET}, async () => {
  assert.equal(process.env.FINANCE_TEST_SOCKET,'/tmp/trip-finance-pg-socket', 'Use the dedicated temporary test socket only');
  const {default:pg}=await import(process.env.FINANCE_TEST_PG_MODULE);
  const config={host:process.env.FINANCE_TEST_SOCKET,port:55992,user:'triptest',database:'postgres'};
  const control=new pg.Client(config); await control.connect();
  const dbName=`finance_test_${randomUUID().replaceAll('-','')}`;
  await control.query(`create database ${dbName}`);
  const a=new pg.Client({...config,database:dbName}), b=new pg.Client({...config,database:dbName}); await a.connect(); await b.connect();
  try {
    await a.query(`do $$ begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if; if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end $$; create schema app_private; create schema auth;
      create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
      create function auth.jwt() returns jsonb language sql as $$ select jsonb_build_object('aal',current_setting('test.aal',true)) $$;
      create function app_private.is_ad_admin() returns boolean language sql as $$ select current_setting('test.admin',true)='true' $$;
      create table auth.users(id uuid primary key,email text);
      create table public.ad_wallets(owner_id uuid primary key,balance_krw bigint not null check(balance_krw>=0),updated_at timestamptz default now());
      create table public.ad_wallet_entries(id uuid primary key default gen_random_uuid(),owner_id uuid not null,kind text not null check(kind in ('credit','debit','refund')),amount_krw bigint not null check(amount_krw between 1 and 1000000000),reference_id uuid not null unique,actor_id uuid,note text not null default '',created_at timestamptz default now(),campaign_id uuid,group_id uuid,draft_id uuid,click_event_id bigint,billing_day date);
      create unique index ad_wallet_entries_one_refund_per_click on public.ad_wallet_entries(click_event_id) where kind='refund';`);
    await a.query(await readFile(new URL('../supabase/migrations/20261111114430_partial_refunds_topup_reversals.sql',import.meta.url),'utf8'));
    const owner='00000000-0000-4000-8000-000000000001', debit='00000000-0000-4000-8000-000000000002';
    await a.query('insert into public.ad_wallets(owner_id,balance_krw) values ($1,0)',[owner]);
    await a.query("insert into public.ad_wallet_entries(id,owner_id,kind,amount_krw,reference_id,click_event_id) values ($1,$2,'debit',100,gen_random_uuid(),42)",[debit,owner]);
    for(const client of [a,b]) await client.query("select set_config('test.uid','00000000-0000-4000-8000-000000000003',false),set_config('test.aal','aal2',false),set_config('test.admin','true',false)");
    await a.query('begin');
    await a.query("select public.partial_ad_click_refund($1,70,'00000000-0000-4000-8000-000000000004','테스트 환불')",[debit]);
    const competing=b.query("select public.partial_ad_click_refund($1,70,'00000000-0000-4000-8000-000000000005','테스트 환불')",[debit]);
    await a.query('commit');
    await assert.rejects(competing,/초과/);
    const result=await a.query("select balance_krw,(select sum(amount_krw) from public.ad_wallet_entries where kind='refund') as refunded from public.ad_wallets where owner_id=$1",[owner]);
    assert.equal(result.rows[0].balance_krw,'70'); assert.equal(result.rows[0].refunded,'70');
    const credit='00000000-0000-4000-8000-000000000006';
    await a.query('update public.ad_wallets set balance_krw=500 where owner_id=$1',[owner]);
    await a.query("insert into public.ad_wallet_entries(id,owner_id,kind,amount_krw,reference_id) values ($1,$2,'credit',300,gen_random_uuid())",[credit,owner]);
    await a.query('begin');
    await a.query("select public.reverse_ad_topup($1,'00000000-0000-4000-8000-000000000007','시험 충전 취소')",[credit]);
    const duplicate=b.query("select public.reverse_ad_topup($1,'00000000-0000-4000-8000-000000000008','시험 충전 취소') as result",[credit]);
    await a.query('commit');
    assert.equal((await duplicate).rows[0].result,'already_reversed');
    const after=await a.query("select balance_krw,(select count(*) from public.ad_wallet_entries where kind='credit_reversal') as reversals from public.ad_wallets where owner_id=$1",[owner]);
    assert.equal(after.rows[0].balance_krw,'200'); assert.equal(after.rows[0].reversals,'1');
  } finally { await a.end(); await b.end(); await control.query(`drop database ${dbName}`); await control.end(); }
});
