create function public.my_ad_costs_exact(p_days integer default 30) returns table(draft_id uuid,cost_krw text)
language sql stable security invoker set search_path='' as $$
 select d.id,coalesce(sum(case when e.kind='debit' then e.amount_krw when e.kind='refund' then -e.amount_krw else 0 end),0)::text
 from public.advertiser_drafts d left join public.ad_wallet_entries e on e.draft_id=d.id and e.kind in ('debit','refund')
 and (p_days=0 or (e.billing_day >= (now() at time zone 'Asia/Seoul')::date-(p_days-1) and e.billing_day <= (now() at time zone 'Asia/Seoul')::date))
 where d.owner_id=(select auth.uid()) and p_days in (0,1,7,30) group by d.id;
$$;
revoke all on function public.my_ad_costs_exact(integer) from public,anon,authenticated;
grant execute on function public.my_ad_costs_exact(integer) to authenticated;
