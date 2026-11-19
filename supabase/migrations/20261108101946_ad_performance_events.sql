create table public.ad_events (
 id bigint generated always as identity primary key,
 ad_id bigint not null references public.sim_ads(id),
 event_type text not null check (event_type in ('loaded','click')),
 created_at timestamptz not null default now()
);
create index ad_events_ad_time_idx on public.ad_events(ad_id, created_at);
create index advertiser_drafts_published_ad_idx on public.advertiser_drafts(published_ad_id);
alter table public.ad_events enable row level security;
revoke all on public.ad_events from public, anon, authenticated;
grant select on public.ad_events to authenticated;
create policy "advertisers see own ad events" on public.ad_events for select to authenticated using (
 exists (select 1 from public.advertiser_drafts d where d.published_ad_id = ad_events.ad_id and d.owner_id = (select auth.uid()))
 or (select app_private.is_ad_admin())
);
create function app_private.record_ad_events(p_ids bigint[], p_event text) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if p_event not in ('loaded','click') or p_event is null or coalesce(cardinality(p_ids),0) not between 1 and 50 then
   raise exception 'invalid event';
 end if;
 insert into public.ad_events(ad_id,event_type)
 select distinct a.id,p_event from public.sim_ads a
 where a.id = any(p_ids) and a.is_active and (a.starts_at is null or a.starts_at <= now()) and (a.ends_at is null or a.ends_at > now());
end;
$$;
revoke all on function app_private.record_ad_events(bigint[],text) from public, anon, authenticated;
grant execute on function app_private.record_ad_events(bigint[],text) to anon, authenticated;
create function public.record_ad_events(p_ids bigint[], p_event text) returns void
language sql security invoker set search_path = '' as $$ select app_private.record_ad_events(p_ids,p_event); $$;
revoke all on function public.record_ad_events(bigint[],text) from public, anon, authenticated;
grant execute on function public.record_ad_events(bigint[],text) to anon, authenticated;
-- Anonymous app clients need access only to the private function, not its data.
grant usage on schema app_private to anon;
create function public.my_ad_performance() returns table(draft_id uuid, loaded bigint, clicks bigint)
language sql stable security invoker set search_path = '' as $$
 select d.id, count(e.id) filter (where e.event_type='loaded'), count(e.id) filter (where e.event_type='click')
 from public.advertiser_drafts d left join public.ad_events e on e.ad_id=d.published_ad_id
 where d.owner_id=(select auth.uid())
 group by d.id;
$$;
revoke all on function public.my_ad_performance() from public, anon, authenticated;
grant execute on function public.my_ad_performance() to authenticated;
