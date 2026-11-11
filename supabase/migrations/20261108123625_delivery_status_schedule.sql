create or replace function app_private.my_ad_delivery() returns table(draft_id uuid,admin_active boolean)
language sql stable security definer set search_path='' as $$
 select d.id,coalesce(a.is_active and (a.starts_at is null or a.starts_at<=now()) and (a.ends_at is null or a.ends_at>now()),false)
 from public.advertiser_drafts d left join public.sim_ads a on a.id=d.published_ad_id where d.owner_id=(select auth.uid()) and d.deleted_at is null;
$$;
