// Run with PGLITE_MODULE pointing to an independently installed, pinned PGlite.
// This exercises the unapplied SQL draft without touching a Supabase project.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

test('financial corrections preserve balances and reject invalid retries', {skip: !process.env.PGLITE_MODULE}, async () => {
  const { PGlite } = await import(process.env.PGLITE_MODULE);
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated;
      create schema app_private; create schema auth;
      create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
      create function auth.jwt() returns jsonb language sql as $$ select jsonb_build_object('aal',current_setting('test.aal',true)) $$;
      create function app_private.is_ad_admin() returns boolean language sql as $$ select coalesce(current_setting('test.admin',true),'false')='true' $$;
      create table auth.users(id uuid primary key,email text);
      create table public.ad_wallets(owner_id uuid primary key, balance_krw bigint not null check(balance_krw>=0),updated_at timestamptz default now());
      create table public.ad_wallet_entries(id uuid primary key default gen_random_uuid(),owner_id uuid not null,kind text not null check(kind in ('credit','debit','refund')),amount_krw bigint not null check(amount_krw between 1 and 1000000000),reference_id uuid not null unique,actor_id uuid,note text not null default '',created_at timestamptz default now(),campaign_id uuid,group_id uuid,draft_id uuid,click_event_id bigint,billing_day date);
      create unique index ad_wallet_entries_one_refund_per_click on public.ad_wallet_entries(click_event_id) where kind='refund';
    `);
    await db.exec(await readFile(new URL('../docs/partial_refunds_topup_reversals.draft.sql', import.meta.url),'utf8'));
    const owner='00000000-0000-4000-8000-000000000001', admin='00000000-0000-4000-8000-000000000002';
    const debit='00000000-0000-4000-8000-000000000003', credit='00000000-0000-4000-8000-000000000004';
    const uuid = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
    await db.query('insert into auth.users values ($1,$2)',[owner,'test@example.test']);
    await db.query('insert into public.ad_wallets(owner_id,balance_krw) values ($1,100)',[owner]);
    await db.query("insert into public.ad_wallet_entries(id,owner_id,kind,amount_krw,reference_id,click_event_id) values ($1,$2,'debit',100,$3,42)",[debit,owner,uuid(5)]);
    await db.query("insert into public.ad_wallet_entries(id,owner_id,kind,amount_krw,reference_id) values ($1,$2,'credit',300,$3)",[credit,owner,uuid(6)]);
    await db.query("select set_config('test.uid',$1,false),set_config('test.admin','true',false),set_config('test.aal','aal1',false)",[admin]);
    const refund=(amount,request) => db.query('select public.partial_ad_click_refund($1,$2,$3,$4) as result',[debit,amount,request,'테스트 환불']);
    await assert.rejects(refund(30,uuid(7)),/2단계/);
    await db.exec("select set_config('test.aal','aal2',false)");
    assert.equal((await refund(30,uuid(7))).rows[0].result,'refunded');
    assert.equal((await refund(30,uuid(7))).rows[0].result,'already_processed');
    await assert.rejects(refund(71,uuid(8)),/초과/);
    assert.equal((await refund(70,uuid(9))).rows[0].result,'refunded');
    assert.equal((await db.query('select balance_krw from public.ad_wallets where owner_id=$1',[owner])).rows[0].balance_krw,200);
    const reverse = request => db.query('select public.reverse_ad_topup($1,$2,$3) as result',[credit,request,'입금 오류 취소']);
    await assert.rejects(reverse(uuid(10)),/잔액이 부족/);
    await db.query('update public.ad_wallets set balance_krw=500 where owner_id=$1',[owner]);
    assert.equal((await reverse(uuid(10))).rows[0].result,'reversed');
    assert.equal((await reverse(uuid(10))).rows[0].result,'already_processed');
    assert.equal((await reverse(uuid(11))).rows[0].result,'already_reversed');
    assert.equal((await db.query('select balance_krw from public.ad_wallets where owner_id=$1',[owner])).rows[0].balance_krw,200);
    await db.exec("select set_config('test.admin','false',false)");
    await assert.rejects(db.query('select * from public.list_ad_corrections()'),/관리자/);
  } finally { await db.close(); }
});
