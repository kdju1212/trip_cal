create or replace function public.my_ad_costs(p_days integer default 30) returns table(draft_id uuid,cost_krw bigint)
language sql stable security invoker set search_path='' as $$
 select d.id,coalesce(sum(e.amount_krw),0)::bigint
 from public.advertiser_drafts d left join public.ad_wallet_entries e on e.draft_id=d.id and e.kind='debit'
 and (p_days=0 or (e.billing_day >= (now() at time zone 'Asia/Seoul')::date-(p_days-1) and e.billing_day <= (now() at time zone 'Asia/Seoul')::date))
 where d.owner_id=(select auth.uid()) and p_days in (0,1,7,30) group by d.id;
$$;
