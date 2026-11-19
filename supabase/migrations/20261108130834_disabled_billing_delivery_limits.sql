-- When billing is eventually enabled, hide ads that cannot fund another click.
-- Paid mode remains disabled until a trusted verification service exists.
create or replace function app_private.advertiser_allows_ad(p_ad_id bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select case
  when not exists(select 1 from public.advertiser_drafts d where d.published_ad_id=p_ad_id)
   then not coalesce((select enabled from app_private.ad_billing_settings where singleton),false)
  else exists(select 1 from public.advertiser_drafts d
   left join public.ad_groups g on g.id=d.group_id and g.owner_id=d.owner_id
   left join public.ad_campaigns c on c.id=g.campaign_id and c.owner_id=g.owner_id
   left join public.ad_wallets w on w.owner_id=d.owner_id
   where d.published_ad_id=p_ad_id and d.review_status='approved' and d.advertiser_enabled and d.deleted_at is null
    and (d.group_id is null or (g.id is not null and g.advertiser_enabled and g.deleted_at is null and c.id is not null and c.advertiser_enabled and c.deleted_at is null))
    and (not coalesce((select enabled from app_private.ad_billing_settings where singleton),false) or
      (g.id is not null and coalesce(w.balance_krw,0)>=g.cpc_bid_krw and
       (c.daily_budget_krw is null or coalesce((select sum(e.amount_krw) from public.ad_wallet_entries e where e.campaign_id=c.id and e.kind='debit' and e.billing_day=(now() at time zone 'Asia/Seoul')::date),0)+g.cpc_bid_krw<=c.daily_budget_krw)))
  ) end;
$$;
