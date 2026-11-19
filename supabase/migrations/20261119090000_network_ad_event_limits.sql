-- Installation ids are chosen by the client, so rotating them bypassed the click
-- checks, and anonymous impression logging had no limit at all. Add a second,
-- network-based signal and cap anonymous ad activity per network.
-- The network address is never stored: it is hashed with a random salt that is
-- replaced every UTC day, and the old salt is deleted so old hashes cannot be linked.

create table app_private.ad_network_salts (
  day date primary key,
  salt text not null
);
alter table app_private.ad_network_salts enable row level security;
revoke all on app_private.ad_network_salts from public, anon, authenticated;

-- Only Cloudflare's cf-connecting-ip is used: the left part of X-Forwarded-For can be
-- set by the client, and X-Real-IP may be a proxy address shared by everyone.
-- Returns null when the address is unavailable; callers must fail closed.
create function app_private.request_network_key() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare v_headers json; v_ip text; v_addr inet; v_day date := (now() at time zone 'UTC')::date; v_salt text;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    return null;
  end;
  v_ip := nullif(trim(v_headers->>'cf-connecting-ip'), '');
  if v_ip is null or char_length(v_ip) > 64 then return null; end if;
  begin
    v_addr := v_ip::inet;
  exception when others then
    return null;
  end;
  -- One IPv6 host usually controls a whole /64, so count it as one network.
  if pg_catalog.family(v_addr) = 6 then
    v_addr := pg_catalog.network(pg_catalog.set_masklen(v_addr, 64));
  end if;
  insert into app_private.ad_network_salts(day, salt)
  values (v_day, gen_random_uuid()::text || gen_random_uuid()::text)
  on conflict (day) do nothing;
  delete from app_private.ad_network_salts where day < v_day;
  select salt into v_salt from app_private.ad_network_salts where day = v_day;
  return encode(pg_catalog.sha256(convert_to(v_salt || ':' || pg_catalog.host(v_addr), 'UTF8')), 'hex');
end;
$$;
revoke all on function app_private.request_network_key() from public, anon, authenticated;

alter table app_private.ad_click_attempts add column network_key text;
create index ad_click_attempts_network_time on app_private.ad_click_attempts(network_key, created_at desc)
  where network_key is not null;

create table app_private.ad_event_attempts (
  id bigint generated always as identity primary key,
  network_key text not null,
  ad_id bigint not null,
  event_type text not null,
  created_at timestamptz not null default now()
);
alter table app_private.ad_event_attempts enable row level security;
revoke all on app_private.ad_event_attempts from public, anon, authenticated;
create index ad_event_attempts_network_time on app_private.ad_event_attempts(network_key, created_at desc);
create index ad_event_attempts_created_at on app_private.ad_event_attempts(created_at);

-- Anonymous impressions / fallback clicks: at most 300 rows per network per minute,
-- and the same ad and event from one network counts once per 30 seconds.
-- Requests without a usable network address share one bucket with the same cap.
create or replace function app_private.record_ad_events(p_ids bigint[], p_event text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_network text; v_used integer; v_room integer;
begin
  if p_event not in ('loaded','click') or p_event is null or coalesce(cardinality(p_ids),0) not between 1 and 50 then
    raise exception 'invalid event';
  end if;
  v_network := coalesce(app_private.request_network_key(), 'unknown');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('ad-events:' || v_network, 0));
  select count(*) into v_used from app_private.ad_event_attempts a
    where a.network_key = v_network and a.created_at > now() - interval '1 minute';
  v_room := 300 - v_used;
  if v_room <= 0 then return; end if;
  with accepted as (
    select distinct a.id from public.sim_ads a
    where a.id = any(p_ids) and app_private.advertiser_allows_ad(a.id) and a.is_active
      and (a.starts_at is null or a.starts_at <= now()) and (a.ends_at is null or a.ends_at > now())
      and not exists (select 1 from app_private.ad_event_attempts r
        where r.network_key = v_network and r.ad_id = a.id and r.event_type = p_event
          and r.created_at > now() - interval '30 seconds')
    order by a.id limit v_room
  ), logged as (
    insert into app_private.ad_event_attempts(network_key, ad_id, event_type)
    select v_network, id, p_event from accepted
  )
  insert into public.ad_events(ad_id, event_type) select id, p_event from accepted;
  -- Incremental cleanup during activity; limit rows are only needed for minutes.
  delete from app_private.ad_event_attempts where id in
    (select id from app_private.ad_event_attempts where created_at < now() - interval '10 minutes' order by created_at limit 500);
end;
$$;

-- Clicks: the installation checks stay; a network signal is added so that rotating
-- installation ids from one network no longer produces 'candidate' clicks.
-- Without a usable network address a click is recorded as 'unverified', never 'candidate'.
create or replace function app_private.record_checked_click(p_ad_id bigint, p_installation_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_device_key text; v_previous_device_key text; v_network text;
  recent_count integer; recent_ads integer; same_ad boolean;
  net_recent integer := 0; net_same_ad integer := 0; net_installs integer := 0; classification text;
begin
  if p_ad_id is null or p_ad_id <= 0 or p_installation_id is null then raise exception 'invalid click'; end if;
  if not exists (select 1 from public.sim_ads a where a.id=p_ad_id and app_private.advertiser_allows_ad(a.id) and a.is_active and (a.starts_at is null or a.starts_at<=now()) and (a.ends_at is null or a.ends_at>now())) then return; end if;
  v_device_key := md5(p_installation_id::text || ':' || (now() at time zone 'UTC')::date::text);
  v_previous_device_key := md5(p_installation_id::text || ':' || ((now() at time zone 'UTC')::date - 1)::text);
  v_network := app_private.request_network_key();
  -- Lock order is always installation, then network.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_installation_id::text,0));
  if v_network is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('ad-clicks:' || v_network, 0));
  end if;
  select count(*), count(distinct ad_id) into recent_count, recent_ads from app_private.ad_click_attempts a
    where a.device_key in (v_device_key,v_previous_device_key) and a.created_at > now()-interval '10 seconds';
  -- Excessive requests are dropped rather than creating unlimited rows.
  if (select count(*) from app_private.ad_click_attempts a where a.device_key in (v_device_key,v_previous_device_key) and a.created_at > now()-interval '1 minute') >= 60 then return; end if;
  if v_network is not null then
    if (select count(*) from app_private.ad_click_attempts a where a.network_key=v_network and a.created_at > now()-interval '1 minute') >= 120 then return; end if;
    select count(*) filter (where a.created_at > now()-interval '1 minute'),
           count(*) filter (where a.created_at > now()-interval '1 minute' and a.ad_id=p_ad_id),
           count(distinct a.device_key)
      into net_recent, net_same_ad, net_installs
      from app_private.ad_click_attempts a
      where a.network_key=v_network and a.created_at > now()-interval '10 minutes';
  end if;
  select exists(select 1 from app_private.ad_click_attempts a where a.device_key in (v_device_key,v_previous_device_key) and a.ad_id=p_ad_id and a.created_at > now()-interval '1 minute') into same_ad;
  classification := case
    when same_ad then 'repeat'
    when recent_count>=4 or recent_ads>=4 then 'suspicious'
    when v_network is null then 'unverified'
    -- Shared mobile networks (CGNAT) can put many people on one address, so these
    -- thresholds are deliberately loose; they only exclude clicks, never block them.
    when net_same_ad>=3 or net_recent>=10 or net_installs>=10 then 'suspicious'
    else 'candidate' end;
  insert into app_private.ad_click_attempts(device_key,ad_id,network_key) values(v_device_key,p_ad_id,v_network);
  insert into public.ad_events(ad_id,event_type,click_classification,bid_at_click_krw)
  select p_ad_id,'click',classification,g.cpc_bid_krw from public.advertiser_drafts d join public.ad_groups g on g.id=d.group_id and g.owner_id=d.owner_id where d.published_ad_id=p_ad_id and d.review_status='approved' and d.deleted_at is null order by d.created_at desc limit 1;
  if not found then insert into public.ad_events(ad_id,event_type,click_classification) values(p_ad_id,'click','unverified'); end if;
  -- Incremental cleanup occurs during activity; it is not a scheduled retention guarantee.
  delete from app_private.ad_click_attempts where id in (select id from app_private.ad_click_attempts where created_at < now()-interval '24 hours' order by created_at limit 100);
end;
$$;
