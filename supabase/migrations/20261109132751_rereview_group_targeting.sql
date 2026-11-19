-- Targeting changes affect every creative in the group. Keep the change and
-- withdrawal of previously approved advertisements in one transaction.
create function app_private.rereview_group_targeting() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (new.sim_type, new.country_code, new.duration_days) is not distinct from
     (old.sim_type, old.country_code, old.duration_days) then
    return new;
  end if;

  -- Reviews lock the creative before updating its published ad. Take locks
  -- in the same order so concurrent review cannot leave an old ad active.
  perform 1 from public.advertiser_drafts d
   where d.group_id = new.id and d.owner_id = new.owner_id and d.deleted_at is null
   order by d.id for update;

  update public.sim_ads a set is_active = false, updated_at = now()
   where exists (
     select 1 from public.advertiser_drafts d
      where d.group_id = new.id and d.owner_id = new.owner_id
        and d.deleted_at is null and d.review_status = 'approved'
        and d.published_ad_id = a.id
   );

  update public.advertiser_drafts d
     set sim_type = new.sim_type,
         country_code = new.country_code,
         duration_days = new.duration_days,
         review_status = case when d.review_status = 'approved' then 'pending' else d.review_status end,
         review_note = case when d.review_status = 'approved' then '' else d.review_note end,
         reviewed_at = case when d.review_status = 'approved' then null else d.reviewed_at end,
         updated_at = now()
   where d.group_id = new.id and d.owner_id = new.owner_id and d.deleted_at is null;
  return new;
end;
$$;
revoke all on function app_private.rereview_group_targeting() from public, anon, authenticated;

create trigger rereview_group_targeting
after update of sim_type, country_code, duration_days on public.ad_groups
for each row execute function app_private.rereview_group_targeting();
