create function app_private.ad_billing_enabled() returns boolean language sql stable security definer set search_path='' as $$ select coalesce((select enabled from app_private.ad_billing_settings where singleton),false); $$;
revoke all on function app_private.ad_billing_enabled() from public,anon,authenticated;
grant execute on function app_private.ad_billing_enabled() to authenticated;
create function public.ad_billing_enabled() returns boolean language sql stable security invoker set search_path='' as $$ select app_private.ad_billing_enabled(); $$;
revoke all on function public.ad_billing_enabled() from public,anon,authenticated;
grant execute on function public.ad_billing_enabled() to authenticated;
create function public.my_ad_costs(p_days integer default 30) returns table(draft_id uuid,cost_krw bigint)
language sql stable security invoker set search_path='' as $$
 select d.id,coalesce(sum(e.amount_krw),0)::bigint
 from public.advertiser_drafts d left join public.ad_wallet_entries e on e.draft_id=d.id and e.kind='debit'
 and (p_days=0 or e.created_at>=((date_trunc('day',now() at time zone 'Asia/Seoul')-make_interval(days=>p_days-1)) at time zone 'Asia/Seoul'))
 where d.owner_id=(select auth.uid()) and p_days in (0,1,7,30) group by d.id;
$$;
revoke all on function public.my_ad_costs(integer) from public,anon,authenticated;
grant execute on function public.my_ad_costs(integer) to authenticated;
create function app_private.list_advertiser_wallets() returns table(owner_id uuid,email text,balance_krw bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 if (select auth.uid()) is null or not app_private.is_ad_admin() then raise exception '관리자 권한이 필요합니다.' using errcode='42501'; end if;
 return query select u.id,u.email::text,coalesce(w.balance_krw,0) from auth.users u left join public.ad_wallets w on w.owner_id=u.id
 where exists(select 1 from public.ad_campaigns c where c.owner_id=u.id) or exists(select 1 from public.advertiser_drafts d where d.owner_id=u.id)
 order by u.email limit 500;
end;
$$;
revoke all on function app_private.list_advertiser_wallets() from public,anon,authenticated;
grant execute on function app_private.list_advertiser_wallets() to authenticated;
create function public.list_advertiser_wallets() returns table(owner_id uuid,email text,balance_krw bigint)
language sql stable security invoker set search_path='' as $$ select * from app_private.list_advertiser_wallets(); $$;
revoke all on function public.list_advertiser_wallets() from public,anon,authenticated;
grant execute on function public.list_advertiser_wallets() to authenticated;
