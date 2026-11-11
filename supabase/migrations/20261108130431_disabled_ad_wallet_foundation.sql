-- Billing is intentionally disabled until trusted click verification and serving limits exist.
create table app_private.ad_billing_settings (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false
);
insert into app_private.ad_billing_settings(singleton,enabled) values(true,false);
alter table app_private.ad_billing_settings enable row level security;
revoke all on app_private.ad_billing_settings from public,anon,authenticated;
create table public.ad_wallets (
 owner_id uuid primary key references auth.users(id),
 balance_krw bigint not null default 0 check(balance_krw>=0),
 updated_at timestamptz not null default now()
);
alter table public.ad_wallets enable row level security;
revoke all on public.ad_wallets from public,anon,authenticated;
grant select on public.ad_wallets to authenticated;
create policy "wallet owner or admin read" on public.ad_wallets for select to authenticated using (owner_id=(select auth.uid()) or (select app_private.is_ad_admin()));
create table public.ad_wallet_entries (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id),
 kind text not null check(kind in ('credit','debit','refund')),
 amount_krw bigint not null check(amount_krw between 1 and 1000000000),
 reference_id uuid not null unique,
 actor_id uuid references auth.users(id),
 note text not null default '' check(char_length(note)<=100),
 created_at timestamptz not null default now()
);
create index ad_wallet_entries_owner_time on public.ad_wallet_entries(owner_id,created_at desc);
alter table public.ad_wallet_entries enable row level security;
revoke all on public.ad_wallet_entries from public,anon,authenticated;
grant select on public.ad_wallet_entries to authenticated;
create policy "wallet entries owner or admin read" on public.ad_wallet_entries for select to authenticated using (owner_id=(select auth.uid()) or (select app_private.is_ad_admin()));
create function app_private.confirm_manual_ad_topup(p_owner uuid,p_amount bigint,p_reference uuid,p_note text) returns void
language plpgsql security definer set search_path='' as $$
declare existing public.ad_wallet_entries%rowtype;
begin
 if (select auth.uid()) is null or not app_private.is_ad_admin() then raise exception '관리자 권한이 필요합니다.' using errcode='42501'; end if;
 if not coalesce((select enabled from app_private.ad_billing_settings where singleton),false) then raise exception '광고 과금은 아직 준비 중입니다.'; end if;
 if p_owner is null or p_reference is null or p_amount is null or p_amount<1 or p_amount>1000000000 or char_length(coalesce(p_note,''))>100 then raise exception '충전 내용을 확인해 주세요.'; end if;
 if not exists(select 1 from auth.users where id=p_owner) then raise exception '광고주 계정을 찾을 수 없습니다.'; end if;
 insert into public.ad_wallets(owner_id) values(p_owner) on conflict(owner_id) do nothing;
 perform 1 from public.ad_wallets where owner_id=p_owner for update;
 select * into existing from public.ad_wallet_entries where reference_id=p_reference;
 if found then
   if existing.owner_id=p_owner and existing.kind='credit' and existing.amount_krw=p_amount then return; end if;
   raise exception '이미 사용된 충전 요청 번호입니다.';
 end if;
 insert into public.ad_wallet_entries(owner_id,kind,amount_krw,reference_id,actor_id,note) values(p_owner,'credit',p_amount,p_reference,(select auth.uid()),coalesce(p_note,''));
 update public.ad_wallets set balance_krw=balance_krw+p_amount,updated_at=now() where owner_id=p_owner;
end;
$$;
revoke all on function app_private.confirm_manual_ad_topup(uuid,bigint,uuid,text) from public,anon,authenticated;
grant execute on function app_private.confirm_manual_ad_topup(uuid,bigint,uuid,text) to authenticated;
create function public.confirm_manual_ad_topup(p_owner uuid,p_amount bigint,p_reference uuid,p_note text default '') returns void
language sql security invoker set search_path='' as $$ select app_private.confirm_manual_ad_topup(p_owner,p_amount,p_reference,p_note); $$;
revoke all on function public.confirm_manual_ad_topup(uuid,bigint,uuid,text) from public,anon,authenticated;
grant execute on function public.confirm_manual_ad_topup(uuid,bigint,uuid,text) to authenticated;
