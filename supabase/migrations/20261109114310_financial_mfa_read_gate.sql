-- Owners can read their own records; administrators need an MFA session to read others' financial records.
create policy "financial wallet MFA for admins" on public.ad_wallets as restrictive for select to authenticated
using (owner_id=(select auth.uid()) or ((select app_private.is_ad_admin()) and (select auth.jwt()->>'aal')='aal2'));
create policy "financial ledger MFA for admins" on public.ad_wallet_entries as restrictive for select to authenticated
using (owner_id=(select auth.uid()) or ((select app_private.is_ad_admin()) and (select auth.jwt()->>'aal')='aal2'));
create or replace function app_private.list_advertiser_wallets() returns table(owner_id uuid,email text,balance_krw bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 if (select auth.uid()) is null or not app_private.is_ad_admin() or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception '2단계 인증된 관리자 권한이 필요합니다.' using errcode='42501'; end if;
 return query select u.id,u.email::text,coalesce(w.balance_krw,0) from auth.users u left join public.ad_wallets w on w.owner_id=u.id
 where exists(select 1 from public.ad_campaigns c where c.owner_id=u.id) or exists(select 1 from public.advertiser_drafts d where d.owner_id=u.id)
 order by u.email limit 500;
end;
$$;
