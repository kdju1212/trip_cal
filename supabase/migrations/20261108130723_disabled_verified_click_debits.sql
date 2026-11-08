alter table public.ad_events add column bid_at_click_krw integer check(bid_at_click_krw>=0);
alter table public.ad_wallet_entries add column campaign_id uuid references public.ad_campaigns(id), add column group_id uuid references public.ad_groups(id), add column draft_id uuid references public.advertiser_drafts(id), add column click_event_id bigint references public.ad_events(id), add column billing_day date;
create unique index ad_wallet_entries_one_debit_per_click on public.ad_wallet_entries(click_event_id) where kind='debit';
create index ad_wallet_entries_campaign_daily_debits on public.ad_wallet_entries(campaign_id,billing_day) where kind='debit';
create table app_private.verified_ad_clicks (
 event_id bigint primary key references public.ad_events(id),
 verified_at timestamptz not null default now(),
 verification_method text not null check(char_length(verification_method) between 1 and 80)
);
alter table app_private.verified_ad_clicks enable row level security;
revoke all on app_private.verified_ad_clicks from public,anon,authenticated;
grant usage on schema app_private to service_role;
grant select,insert on app_private.verified_ad_clicks to service_role;
-- Only a future trusted verification service may mark an event as verified.
create function app_private.charge_verified_ad_click(p_event_id bigint) returns text
language plpgsql security definer set search_path='' as $$
declare e public.ad_events%rowtype; d public.advertiser_drafts%rowtype; g public.ad_groups%rowtype; c public.ad_campaigns%rowtype; w public.ad_wallets%rowtype; spent bigint; day_kst date;
begin
 if not coalesce((select enabled from app_private.ad_billing_settings where singleton),false) then raise exception '광고 과금은 아직 준비 중입니다.'; end if;
 select * into e from public.ad_events where id=p_event_id for update;
 if not found or e.event_type<>'click' or e.click_classification<>'candidate' or e.bid_at_click_krw is null then raise exception '청구 가능한 클릭을 찾을 수 없습니다.'; end if;
 if not exists(select 1 from app_private.verified_ad_clicks where event_id=e.id) then raise exception '클릭 검증이 필요합니다.' using errcode='42501'; end if;
 if exists(select 1 from public.ad_wallet_entries where kind='debit' and click_event_id=e.id) then return 'already_charged'; end if;
 select * into d from public.advertiser_drafts where published_ad_id=e.ad_id and review_status='approved' and deleted_at is null and advertiser_enabled for update;
 if not found or d.group_id is null then return 'not_eligible'; end if;
 select * into g from public.ad_groups where id=d.group_id and owner_id=d.owner_id and deleted_at is null and advertiser_enabled;
 if not found then return 'not_eligible'; end if;
 select * into c from public.ad_campaigns where id=g.campaign_id and owner_id=d.owner_id and deleted_at is null and advertiser_enabled for update;
 if not found or not exists(select 1 from public.sim_ads a where a.id=e.ad_id and a.is_active and (a.starts_at is null or a.starts_at<=now()) and (a.ends_at is null or a.ends_at>now())) then return 'not_eligible'; end if;
 if e.created_at < now()-interval '24 hours' or e.created_at>now() then return 'expired'; end if;
 day_kst := (e.created_at at time zone 'Asia/Seoul')::date;
 select coalesce(sum(amount_krw),0) into spent from public.ad_wallet_entries where kind='debit' and campaign_id=c.id and billing_day=day_kst;
 if c.daily_budget_krw is not null and spent+e.bid_at_click_krw>c.daily_budget_krw then return 'budget_exhausted'; end if;
 if e.bid_at_click_krw=0 then return 'zero_bid'; end if;
 select * into w from public.ad_wallets where owner_id=d.owner_id for update;
 if not found or w.balance_krw<e.bid_at_click_krw then return 'insufficient_balance'; end if;
 insert into public.ad_wallet_entries(owner_id,kind,amount_krw,reference_id,campaign_id,group_id,draft_id,click_event_id,billing_day,note)
 values(d.owner_id,'debit',e.bid_at_click_krw,gen_random_uuid(),c.id,g.id,d.id,e.id,day_kst,'검증된 광고 클릭');
 update public.ad_wallets set balance_krw=balance_krw-e.bid_at_click_krw,updated_at=now() where owner_id=d.owner_id;
 return 'charged';
end;
$$;
revoke all on function app_private.charge_verified_ad_click(bigint) from public,anon,authenticated,service_role;
grant execute on function app_private.charge_verified_ad_click(bigint) to service_role;
create function public.charge_verified_ad_click(p_event_id bigint) returns text
language sql security invoker set search_path='' as $$ select app_private.charge_verified_ad_click(p_event_id); $$;
revoke all on function public.charge_verified_ad_click(bigint) from public,anon,authenticated,service_role;
grant execute on function public.charge_verified_ad_click(bigint) to service_role;

create or replace function app_private.record_checked_click(p_ad_id bigint,p_installation_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_device_key text; v_previous_device_key text; recent_count integer; recent_ads integer; same_ad boolean; classification text;
begin
 if p_ad_id is null or p_ad_id <= 0 or p_installation_id is null then raise exception 'invalid click'; end if;
 if not exists (select 1 from public.sim_ads a where a.id=p_ad_id and app_private.advertiser_allows_ad(a.id) and a.is_active and (a.starts_at is null or a.starts_at<=now()) and (a.ends_at is null or a.ends_at>now())) then return; end if;
 -- A rotating digest limits linkage between days; no IP address is stored here.
 v_device_key := md5(p_installation_id::text || ':' || (now() at time zone 'UTC')::date::text);
 v_previous_device_key := md5(p_installation_id::text || ':' || ((now() at time zone 'UTC')::date - 1)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_installation_id::text,0));
 select count(*), count(distinct ad_id) into recent_count,recent_ads from app_private.ad_click_attempts a where a.device_key in (v_device_key,v_previous_device_key) and a.created_at > now()-interval '10 seconds';
 -- Excessive requests are dropped rather than creating unlimited rows for this identifier.
 if (select count(*) from app_private.ad_click_attempts a where a.device_key in (v_device_key,v_previous_device_key) and a.created_at > now()-interval '1 minute') >= 60 then return; end if;
 select exists(select 1 from app_private.ad_click_attempts a where a.device_key in (v_device_key,v_previous_device_key) and a.ad_id=p_ad_id and a.created_at > now()-interval '1 minute') into same_ad;
 classification := case when same_ad then 'repeat' when recent_count>=4 or recent_ads>=4 then 'suspicious' else 'candidate' end;
 insert into app_private.ad_click_attempts(device_key,ad_id) values(v_device_key,p_ad_id);
 insert into public.ad_events(ad_id,event_type,click_classification,bid_at_click_krw)
 select p_ad_id,'click',classification,g.cpc_bid_krw from public.advertiser_drafts d join public.ad_groups g on g.id=d.group_id and g.owner_id=d.owner_id where d.published_ad_id=p_ad_id and d.review_status='approved' and d.deleted_at is null order by d.created_at desc limit 1;
 if not found then insert into public.ad_events(ad_id,event_type,click_classification) values(p_ad_id,'click','unverified'); end if;
 -- Incremental cleanup occurs during activity; it is not a scheduled retention guarantee.
 delete from app_private.ad_click_attempts where id in (select id from app_private.ad_click_attempts where created_at < now()-interval '24 hours' order by created_at limit 100);
end;
$$;
