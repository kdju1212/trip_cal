alter table public.ad_events add column click_classification text not null default 'unverified' check (click_classification in ('unverified','candidate','repeat','suspicious'));
create table app_private.ad_click_attempts (
  id bigint generated always as identity primary key,
  device_key text not null,
  ad_id bigint not null references public.sim_ads(id),
  created_at timestamptz not null default now()
);
alter table app_private.ad_click_attempts enable row level security;
revoke all on app_private.ad_click_attempts from public, anon, authenticated;
create index ad_click_attempts_device_time on app_private.ad_click_attempts(device_key,created_at desc);
create index ad_click_attempts_created_at on app_private.ad_click_attempts(created_at);
create function app_private.record_checked_click(p_ad_id bigint,p_installation_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare device_key text; recent_count integer; recent_ads integer; same_ad boolean; classification text;
begin
 if p_ad_id is null or p_ad_id <= 0 or p_installation_id is null then raise exception 'invalid click'; end if;
 if not exists (select 1 from public.sim_ads a where a.id=p_ad_id and a.is_active and (a.starts_at is null or a.starts_at<=now()) and (a.ends_at is null or a.ends_at>now())) then return; end if;
 -- A rotating digest limits linkage between days; no IP address is stored here.
 device_key := md5(p_installation_id::text || ':' || (now() at time zone 'UTC')::date::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(device_key,0));
 select count(*), count(distinct ad_id) into recent_count,recent_ads from app_private.ad_click_attempts a where a.device_key=device_key and a.created_at > now()-interval '10 seconds';
 -- Excessive requests are dropped rather than creating unlimited rows for this identifier.
 if (select count(*) from app_private.ad_click_attempts a where a.device_key=device_key and a.created_at > now()-interval '1 minute') >= 60 then return; end if;
 select exists(select 1 from app_private.ad_click_attempts a where a.device_key=device_key and a.ad_id=p_ad_id and a.created_at > now()-interval '1 minute') into same_ad;
 classification := case when same_ad then 'repeat' when recent_count>=4 or recent_ads>=4 then 'suspicious' else 'candidate' end;
 insert into app_private.ad_click_attempts(device_key,ad_id) values(device_key,p_ad_id);
 insert into public.ad_events(ad_id,event_type,click_classification) values(p_ad_id,'click',classification);
 -- Incremental cleanup occurs during activity; it is not a scheduled retention guarantee.
 delete from app_private.ad_click_attempts where id in (select id from app_private.ad_click_attempts where created_at < now()-interval '24 hours' order by created_at limit 100);
end;
$$;
revoke all on function app_private.record_checked_click(bigint,uuid) from public,anon,authenticated;
grant execute on function app_private.record_checked_click(bigint,uuid) to anon,authenticated;
create function public.record_checked_click(p_ad_id bigint,p_installation_id uuid) returns void
language sql security invoker set search_path = '' as $$ select app_private.record_checked_click(p_ad_id,p_installation_id); $$;
revoke all on function public.record_checked_click(bigint,uuid) from public,anon,authenticated;
grant execute on function public.record_checked_click(bigint,uuid) to anon,authenticated;
create function public.my_ad_performance_breakdown(p_days integer default 30)
returns table(draft_id uuid,loaded bigint,clicks bigint,candidate bigint,excluded bigint,unverified bigint)
language sql stable security invoker set search_path = '' as $$
 select d.id,count(e.id) filter (where e.event_type='loaded'), count(e.id) filter (where e.event_type='click'),
 count(e.id) filter (where e.event_type='click' and e.click_classification='candidate'),
 count(e.id) filter (where e.event_type='click' and e.click_classification in ('repeat','suspicious')),
 count(e.id) filter (where e.event_type='click' and e.click_classification='unverified')
 from public.advertiser_drafts d left join public.ad_events e on e.ad_id=d.published_ad_id
 and (p_days=0 or e.created_at>=((date_trunc('day',now() at time zone 'Asia/Seoul')-make_interval(days=>p_days-1)) at time zone 'Asia/Seoul'))
 where d.owner_id=(select auth.uid()) and p_days in (0,1,7,30) group by d.id;
$$;
revoke all on function public.my_ad_performance_breakdown(integer) from public,anon,authenticated;
grant execute on function public.my_ad_performance_breakdown(integer) to authenticated;
