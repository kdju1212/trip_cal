create table app_private.ad_action_audit (
 id bigint generated always as identity primary key,
 entity_kind text not null,
 entity_id text not null,
 action text not null,
 actor_id uuid,
 detail jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index ad_action_audit_time on app_private.ad_action_audit(created_at desc,id desc);
alter table app_private.ad_action_audit enable row level security;
revoke all on app_private.ad_action_audit from public,anon,authenticated;
create function app_private.audit_ad_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare before_row jsonb; after_row jsonb := to_jsonb(new); field text;
begin
 if tg_op='INSERT' then
   insert into app_private.ad_action_audit(entity_kind,entity_id,action,actor_id) values(tg_table_name,after_row->>'id','created',(select auth.uid()));
 else
   before_row:=to_jsonb(old);
   foreach field in array array['review_status','advertiser_enabled','deleted_at','is_active'] loop
     if before_row ? field and after_row ? field and (before_row->field) is distinct from (after_row->field) then
       insert into app_private.ad_action_audit(entity_kind,entity_id,action,actor_id,detail)
       values(tg_table_name,after_row->>'id',field,(select auth.uid()),jsonb_build_object('before',before_row->field,'after',after_row->field));
     end if;
   end loop;
 end if;
 return new;
end;
$$;
revoke all on function app_private.audit_ad_change() from public,anon,authenticated;
create trigger audit_campaign_change after insert or update on public.ad_campaigns for each row execute function app_private.audit_ad_change();
create trigger audit_group_change after insert or update on public.ad_groups for each row execute function app_private.audit_ad_change();
create trigger audit_creative_change after insert or update on public.advertiser_drafts for each row execute function app_private.audit_ad_change();
create trigger audit_live_ad_change after insert or update on public.sim_ads for each row execute function app_private.audit_ad_change();
create function app_private.list_ad_action_audit() returns table(entity_kind text,entity_id text,action text,actor_email text,detail jsonb,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if (select auth.uid()) is null or not app_private.is_ad_admin() or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception '2단계 인증된 관리자 권한이 필요합니다.' using errcode='42501'; end if;
 return query select a.entity_kind,a.entity_id,a.action,u.email::text,a.detail,a.created_at from app_private.ad_action_audit a left join auth.users u on u.id=a.actor_id order by a.created_at desc,a.id desc limit 100;
end;
$$;
revoke all on function app_private.list_ad_action_audit() from public,anon,authenticated;
grant execute on function app_private.list_ad_action_audit() to authenticated;
create function public.list_ad_action_audit() returns table(entity_kind text,entity_id text,action text,actor_email text,detail jsonb,created_at timestamptz)
language sql stable security invoker set search_path='' as $$ select * from app_private.list_ad_action_audit(); $$;
revoke all on function public.list_ad_action_audit() from public,anon,authenticated;
grant execute on function public.list_ad_action_audit() to authenticated;
