create function public.my_ad_performance_period(p_days integer default 30)
returns table(draft_id uuid, loaded bigint, clicks bigint)
language sql stable security invoker set search_path = '' as $$
  select d.id, count(e.id) filter (where e.event_type = 'loaded'), count(e.id) filter (where e.event_type = 'click')
  from public.advertiser_drafts d
  left join public.ad_events e on e.ad_id = d.published_ad_id
    and (p_days = 0 or e.created_at >= ((date_trunc('day', now() at time zone 'Asia/Seoul') - make_interval(days => p_days - 1)) at time zone 'Asia/Seoul'))
  where d.owner_id = (select auth.uid()) and p_days in (0,1,7,30)
  group by d.id;
$$;
revoke all on function public.my_ad_performance_period(integer) from public, anon, authenticated;
grant execute on function public.my_ad_performance_period(integer) to authenticated;
