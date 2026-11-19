// Independent Postgres instance only. Set AD_TEST_PG_MODULE (path to an installed `pg`
// package) and AD_TEST_PG_URL (an admin connection to a throwaway server) to opt in.
// A temporary database is created and dropped; never point this at a Supabase project.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';

const enabled = process.env.AD_TEST_PG_MODULE && process.env.AD_TEST_PG_URL;
const migration = new URL('../supabase/migrations/20261119090000_network_ad_event_limits.sql', import.meta.url);

async function withDatabase(run) {
  const {default: pg} = await import(process.env.AD_TEST_PG_MODULE);
  const control = new pg.Client({connectionString: process.env.AD_TEST_PG_URL});
  await control.connect();
  const name = `ad_limits_test_${randomUUID().replaceAll('-', '')}`;
  await control.query(`create database ${name}`);
  const url = new URL(process.env.AD_TEST_PG_URL); url.pathname = `/${name}`;
  const db = new pg.Client({connectionString: url.toString()});
  try {
    await db.connect();
    // Minimal stand-ins for the tables and helpers created by earlier migrations.
    await db.query(`
      do $$ begin create role anon; exception when duplicate_object then null; end $$;
      do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
      create schema app_private;
      create table public.sim_ads(id bigint primary key, is_active boolean not null default true, starts_at timestamptz, ends_at timestamptz);
      create function app_private.advertiser_allows_ad(bigint) returns boolean language sql as $$ select true $$;
      create table public.ad_events(id bigint generated always as identity primary key, ad_id bigint not null references public.sim_ads(id),
        event_type text not null, click_classification text not null default 'unverified', bid_at_click_krw integer, created_at timestamptz not null default now());
      create table app_private.ad_click_attempts(id bigint generated always as identity primary key, device_key text not null,
        ad_id bigint not null references public.sim_ads(id), created_at timestamptz not null default now());
      create table public.ad_groups(id uuid primary key, owner_id uuid not null, cpc_bid_krw integer);
      create table public.advertiser_drafts(id uuid primary key, owner_id uuid not null, group_id uuid, published_ad_id bigint,
        review_status text not null, deleted_at timestamptz, created_at timestamptz not null default now());
      insert into public.sim_ads(id) select generate_series(1, 60);
      -- Clicks are classified only for ads published from an approved advertiser draft.
      insert into public.ad_groups values ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002',100);
      insert into public.advertiser_drafts(id, owner_id, group_id, published_ad_id, review_status)
        select gen_random_uuid(),'00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001',i,'approved' from generate_series(1, 60) i;
    `);
    await db.query(await readFile(migration, 'utf8'));
    // Public wrappers, as created by the earlier migrations.
    await db.query(`
      create function public.record_ad_events(p_ids bigint[], p_event text) returns void language sql as $$ select app_private.record_ad_events(p_ids,p_event) $$;
      create function public.record_checked_click(p_ad_id bigint, p_installation_id uuid) returns void language sql as $$ select app_private.record_checked_click(p_ad_id,p_installation_id) $$;
    `);
    await run(db);
  } finally {
    await db.end();
    await control.query(`drop database if exists ${name} with (force)`);
    await control.end();
  }
}

const fromIp = (db, ip) => db.query("select set_config('request.headers', $1, false)",
  [ip === null ? '{}' : JSON.stringify({'cf-connecting-ip': ip, 'x-forwarded-for': '6.6.6.6'})]);
const click = (db, ad, installation = randomUUID()) => db.query('select public.record_checked_click($1,$2)', [ad, installation]);
const classes = async db => Object.fromEntries((await db.query(
  "select click_classification c, count(*)::int n from public.ad_events where event_type='click' group by 1")).rows.map(r => [r.c, r.n]));
const events = async (db, type) => (await db.query('select count(*)::int n from public.ad_events where event_type=$1', [type])).rows[0].n;

test('rotating installation ids from one network no longer yields candidate clicks', {skip: !enabled}, async () => {
  await withDatabase(async db => {
    await fromIp(db, '203.0.113.7');
    for (let i = 0; i < 20; i++) await click(db, 1);
    const result = await classes(db);
    assert.equal(result.candidate, 3, 'only the first clicks on one ad from one network are candidates');
    assert.equal(result.suspicious, 17);
    // A different network is unaffected, and the client-controlled X-Forwarded-For is ignored.
    await fromIp(db, '198.51.100.9');
    await click(db, 1);
    assert.equal((await classes(db)).candidate, 4);
    // Network addresses are never stored in plain text.
    const keys = (await db.query('select distinct network_key from app_private.ad_click_attempts')).rows.map(r => r.network_key);
    assert.equal(keys.length, 2);
    for (const key of keys) assert.match(key, /^[0-9a-f]{64}$/);
  });
});

test('clicks without a trusted network address are never candidates', {skip: !enabled}, async () => {
  await withDatabase(async db => {
    await fromIp(db, null);
    await click(db, 1);
    await db.query("select set_config('request.headers', $1, false)", [JSON.stringify({'x-forwarded-for': '203.0.113.7'})]);
    await click(db, 2);
    await fromIp(db, 'not-an-address');
    await click(db, 3);
    assert.deepEqual(await classes(db), {unverified: 3});
  });
});

test('one IPv6 /64 counts as one network and click floods are dropped', {skip: !enabled}, async () => {
  await withDatabase(async db => {
    for (let i = 0; i < 130; i++) {
      await fromIp(db, `2001:db8:1:2::${(i + 1).toString(16)}`);
      await click(db, (i % 50) + 1);
    }
    assert.equal(await events(db, 'click'), 120, 'clicks beyond 120 per minute per network are not recorded');
    assert.equal((await classes(db)).candidate, 10);
  });
});

test('anonymous impressions are deduplicated and capped per network', {skip: !enabled}, async () => {
  await withDatabase(async db => {
    await fromIp(db, '203.0.113.7');
    const ids = Array.from({length: 50}, (_, i) => i + 1);
    await db.query('select public.record_ad_events($1,$2)', [ids, 'loaded']);
    await db.query('select public.record_ad_events($1,$2)', [ids, 'loaded']);
    assert.equal(await events(db, 'loaded'), 50, 'repeated loads within 30 seconds count once');
    await db.query("update app_private.ad_event_attempts set created_at = now() - interval '31 seconds'");
    for (let i = 0; i < 10; i++) {
      await db.query('select public.record_ad_events($1,$2)', [ids, 'loaded']);
      await db.query("update app_private.ad_event_attempts set created_at = now() - interval '31 seconds' where created_at > now() - interval '31 seconds'");
    }
    assert.equal(await events(db, 'loaded'), 300, 'at most 300 events per network per minute');
    await fromIp(db, '198.51.100.9');
    await db.query('select public.record_ad_events($1,$2)', [[1, 2, 3], 'loaded']);
    assert.equal(await events(db, 'loaded'), 303, 'other networks keep their own allowance');
    await assert.rejects(db.query('select public.record_ad_events($1,$2)', [[], 'loaded']), /invalid event/);
  });
});

test('the salt rotates daily and old salts are removed', {skip: !enabled}, async () => {
  await withDatabase(async db => {
    await db.query("insert into app_private.ad_network_salts values ((now() at time zone 'UTC')::date - 1, 'old')");
    await fromIp(db, '203.0.113.7');
    await click(db, 1);
    const salts = (await db.query('select day, salt from app_private.ad_network_salts')).rows;
    assert.equal(salts.length, 1);
    assert.notEqual(salts[0].salt, 'old');
    assert.ok(salts[0].salt.length >= 64);
  });
});
