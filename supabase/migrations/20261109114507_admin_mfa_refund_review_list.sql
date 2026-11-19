create function app_private.list_ad_debits_for_refund() returns table(debit_id uuid,email text,amount_krw bigint,campaign text,ad_title text,billing_day date,refunded boolean,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if (select auth.uid()) is null or not app_private.is_ad_admin() or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception '2단계 인증된 관리자 권한이 필요합니다.' using errcode='42501'; end if;
 return query select e.id,u.email::text,e.amount_krw,coalesce(c.name,''),coalesce(d.title,''),e.billing_day,
 exists(select 1 from public.ad_wallet_entries r where r.kind='refund' and r.click_event_id=e.click_event_id),e.created_at
 from public.ad_wallet_entries e join auth.users u on u.id=e.owner_id left join public.ad_campaigns c on c.id=e.campaign_id left join public.advertiser_drafts d on d.id=e.draft_id
 where e.kind='debit' and e.click_event_id is not null order by e.created_at desc limit 100;
end;
$$;
revoke all on function app_private.list_ad_debits_for_refund() from public,anon,authenticated;
grant execute on function app_private.list_ad_debits_for_refund() to authenticated;
create function public.list_ad_debits_for_refund() returns table(debit_id uuid,email text,amount_krw bigint,campaign text,ad_title text,billing_day date,refunded boolean,created_at timestamptz)
language sql stable security invoker set search_path='' as $$ select * from app_private.list_ad_debits_for_refund(); $$;
revoke all on function public.list_ad_debits_for_refund() from public,anon,authenticated;
grant execute on function public.list_ad_debits_for_refund() to authenticated;
