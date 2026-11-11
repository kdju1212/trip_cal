-- MFA enforcement is opt-in and cannot be enabled without an already verified factor and AAL2 session.
create table app_private.ad_security_settings(singleton boolean primary key default true check(singleton),admin_mfa_required boolean not null default false);
insert into app_private.ad_security_settings(singleton,admin_mfa_required) values(true,false);
alter table app_private.ad_security_settings enable row level security;
revoke all on app_private.ad_security_settings from public,anon,authenticated;
create function app_private.is_ad_admin_member() returns boolean language sql stable security definer set search_path='' as $$
 select (select auth.uid()) is not null and exists(select 1 from public.ad_admins where user_id=(select auth.uid()));
$$;
revoke all on function app_private.is_ad_admin_member() from public,anon,authenticated;
grant execute on function app_private.is_ad_admin_member() to authenticated;
create or replace function app_private.is_ad_admin() returns boolean language sql stable security definer set search_path='' as $$
 select app_private.is_ad_admin_member() and (not coalesce((select admin_mfa_required from app_private.ad_security_settings where singleton),true) or coalesce((select auth.jwt()->>'aal'),'')='aal2');
$$;
-- The public identity check is not an authorization grant. It lets an AAL1 admin reach the MFA challenge.
create or replace function public.is_ad_admin() returns boolean language sql stable security invoker set search_path='' as $$ select app_private.is_ad_admin_member(); $$;
create function app_private.admin_security_status() returns table(mfa_required boolean)
language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.is_ad_admin_member() then raise exception '관리자 권한이 필요합니다.' using errcode='42501'; end if;
 return query select s.admin_mfa_required from app_private.ad_security_settings s where s.singleton;
end;
$$;
revoke all on function app_private.admin_security_status() from public,anon,authenticated;
grant execute on function app_private.admin_security_status() to authenticated;
create function public.admin_security_status() returns table(mfa_required boolean)
language sql stable security invoker set search_path='' as $$ select * from app_private.admin_security_status(); $$;
revoke all on function public.admin_security_status() from public,anon,authenticated;
grant execute on function public.admin_security_status() to authenticated;
create function app_private.enable_admin_mfa_enforcement() returns void
language plpgsql security definer set search_path='' as $$
begin
 if not app_private.is_ad_admin_member() or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception '2단계 인증된 관리자 권한이 필요합니다.' using errcode='42501'; end if;
 if not exists(select 1 from auth.mfa_factors where user_id=(select auth.uid()) and status='verified' and factor_type='totp') then raise exception '인증 앱 등록이 필요합니다.'; end if;
 update app_private.ad_security_settings set admin_mfa_required=true where singleton and not admin_mfa_required;
 if found then insert into app_private.ad_action_audit(entity_kind,entity_id,action,actor_id,detail) values('ad_security_settings','global','admin_mfa_required',(select auth.uid()),jsonb_build_object('before',false,'after',true)); end if;
end;
$$;
revoke all on function app_private.enable_admin_mfa_enforcement() from public,anon,authenticated;
grant execute on function app_private.enable_admin_mfa_enforcement() to authenticated;
create function public.enable_admin_mfa_enforcement() returns void
language sql security invoker set search_path='' as $$ select app_private.enable_admin_mfa_enforcement(); $$;
revoke all on function public.enable_admin_mfa_enforcement() from public,anon,authenticated;
grant execute on function public.enable_admin_mfa_enforcement() to authenticated;
