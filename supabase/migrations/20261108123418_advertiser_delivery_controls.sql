alter table public.ad_campaigns add column advertiser_enabled boolean not null default true, add column deleted_at timestamptz;
alter table public.ad_groups add column advertiser_enabled boolean not null default true, add column deleted_at timestamptz;
alter table public.advertiser_drafts add column advertiser_enabled boolean not null default true, add column deleted_at timestamptz;
create function app_private.advertiser_allows_ad(p_ad_id bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.advertiser_drafts d where d.published_ad_id=p_ad_id)
 or exists(select 1 from public.advertiser_drafts d
 left join public.ad_groups g on g.id=d.group_id and g.owner_id=d.owner_id
 left join public.ad_campaigns c on c.id=g.campaign_id and c.owner_id=g.owner_id
 where d.published_ad_id=p_ad_id and d.review_status='approved' and d.advertiser_enabled and d.deleted_at is null
 and (d.group_id is null or (g.id is not null and g.advertiser_enabled and g.deleted_at is null and c.id is not null and c.advertiser_enabled and c.deleted_at is null)));
$$;
revoke all on function app_private.advertiser_allows_ad(bigint) from public,anon,authenticated;
grant execute on function app_private.advertiser_allows_ad(bigint) to anon,authenticated;
create policy "advertiser delivery gate anonymous" on public.sim_ads as restrictive for select to anon using (app_private.advertiser_allows_ad(id));
create policy "advertiser delivery gate authenticated" on public.sim_ads as restrictive for select to authenticated using (app_private.advertiser_allows_ad(id) or (select app_private.is_ad_admin()));
create policy "group must belong to live campaign" on public.ad_groups as restrictive for insert to authenticated with check (exists(select 1 from public.ad_campaigns c where c.id=ad_groups.campaign_id and c.owner_id=(select auth.uid()) and c.deleted_at is null));
create policy "draft must belong to live group" on public.advertiser_drafts as restrictive for insert to authenticated with check (group_id is null or exists(select 1 from public.ad_groups g join public.ad_campaigns c on c.id=g.campaign_id and c.owner_id=g.owner_id where g.id=advertiser_drafts.group_id and g.owner_id=(select auth.uid()) and g.deleted_at is null and c.deleted_at is null));
create function app_private.set_advertiser_delivery(p_kind text,p_id uuid,p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if (select auth.uid()) is null or p_enabled is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 if p_kind='campaign' then update public.ad_campaigns set advertiser_enabled=p_enabled where id=p_id and owner_id=(select auth.uid()) and deleted_at is null;
 elsif p_kind='group' then update public.ad_groups set advertiser_enabled=p_enabled where id=p_id and owner_id=(select auth.uid()) and deleted_at is null;
 elsif p_kind='creative' then update public.advertiser_drafts set advertiser_enabled=p_enabled,updated_at=now() where id=p_id and owner_id=(select auth.uid()) and deleted_at is null;
 else raise exception '잘못된 항목입니다.'; end if;
 if not found then raise exception '항목을 찾을 수 없습니다.'; end if;
end;
$$;
revoke all on function app_private.set_advertiser_delivery(text,uuid,boolean) from public,anon,authenticated;
grant execute on function app_private.set_advertiser_delivery(text,uuid,boolean) to authenticated;
create function public.set_advertiser_delivery(p_kind text,p_id uuid,p_enabled boolean) returns void
language sql security invoker set search_path='' as $$ select app_private.set_advertiser_delivery(p_kind,p_id,p_enabled); $$;
revoke all on function public.set_advertiser_delivery(text,uuid,boolean) from public,anon,authenticated;
grant execute on function public.set_advertiser_delivery(text,uuid,boolean) to authenticated;
create function app_private.delete_advertiser_item(p_kind text,p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare owner uuid := (select auth.uid());
begin
 if owner is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 if p_kind='campaign' then
   update public.ad_campaigns set deleted_at=now(),advertiser_enabled=false where id=p_id and owner_id=owner and deleted_at is null;
   if not found then raise exception '항목을 찾을 수 없습니다.'; end if;
   update public.advertiser_drafts d set deleted_at=now(),advertiser_enabled=false,updated_at=now() where d.owner_id=owner and d.deleted_at is null and exists(select 1 from public.ad_groups g where g.id=d.group_id and g.owner_id=owner and g.campaign_id=p_id);
   update public.ad_groups set deleted_at=now(),advertiser_enabled=false where campaign_id=p_id and owner_id=owner and deleted_at is null;
 elsif p_kind='group' then
   update public.ad_groups set deleted_at=now(),advertiser_enabled=false where id=p_id and owner_id=owner and deleted_at is null;
   if not found then raise exception '항목을 찾을 수 없습니다.'; end if;
   update public.advertiser_drafts set deleted_at=now(),advertiser_enabled=false,updated_at=now() where group_id=p_id and owner_id=owner and deleted_at is null;
 elsif p_kind='creative' then
   update public.advertiser_drafts set deleted_at=now(),advertiser_enabled=false,updated_at=now() where id=p_id and owner_id=owner and deleted_at is null;
   if not found then raise exception '항목을 찾을 수 없습니다.'; end if;
 else raise exception '잘못된 항목입니다.'; end if;
end;
$$;
revoke all on function app_private.delete_advertiser_item(text,uuid) from public,anon,authenticated;
grant execute on function app_private.delete_advertiser_item(text,uuid) to authenticated;
create function public.delete_advertiser_item(p_kind text,p_id uuid) returns void
language sql security invoker set search_path='' as $$ select app_private.delete_advertiser_item(p_kind,p_id); $$;
revoke all on function public.delete_advertiser_item(text,uuid) from public,anon,authenticated;
grant execute on function public.delete_advertiser_item(text,uuid) to authenticated;
create function app_private.my_ad_delivery() returns table(draft_id uuid,admin_active boolean)
language sql stable security definer set search_path='' as $$
 select d.id,coalesce(a.is_active,false) from public.advertiser_drafts d left join public.sim_ads a on a.id=d.published_ad_id where d.owner_id=(select auth.uid()) and d.deleted_at is null;
$$;
revoke all on function app_private.my_ad_delivery() from public,anon,authenticated;
grant execute on function app_private.my_ad_delivery() to authenticated;
create function public.my_ad_delivery() returns table(draft_id uuid,admin_active boolean)
language sql stable security invoker set search_path='' as $$ select * from app_private.my_ad_delivery(); $$;
revoke all on function public.my_ad_delivery() from public,anon,authenticated;
grant execute on function public.my_ad_delivery() to authenticated;
create or replace function app_private.list_ranked_sim_ads(p_country text,p_type text,p_days integer default null)
returns table(id bigint,merchant_name text,title text,description text,sim_type text,country_code text,duration_days integer,price_krw integer,image_url text,purchase_url text,priority integer,updated_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select a.id,a.merchant_name,a.title,a.description,a.sim_type,a.country_code,a.duration_days,a.price_krw,a.image_url,a.purchase_url,a.priority,a.updated_at
  from public.sim_ads a
  left join lateral (select max(g.cpc_bid_krw) as bid from public.advertiser_drafts d join public.ad_groups g on g.id=d.group_id and g.owner_id=d.owner_id where d.published_ad_id=a.id and d.review_status='approved') rank_data on true
  where p_country ~ '^[A-Z]{2}$' and p_type in ('sim','esim') and (p_days is null or p_days between 1 and 365)
    and a.country_code=p_country and a.sim_type=p_type and (p_days is null or a.duration_days=p_days)
    and app_private.advertiser_allows_ad(a.id) and a.is_active and (a.starts_at is null or a.starts_at<=now()) and (a.ends_at is null or a.ends_at>now())
  order by coalesce(rank_data.bid,0) desc,a.priority desc,a.id desc limit 50;
$$;
create or replace function app_private.record_checked_click(p_ad_id bigint,p_installation_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_device_key text; v_previous_device_key text; recent_count integer; recent_ads integer; same_ad boolean; classification text;
begin
 if p_ad_id is null or p_ad_id <= 0 or p_installation_id is null then raise exception 'invalid click'; end if;
 if not exists (select 1 from public.sim_ads a where a.id=p_ad_id and app_private.advertiser_allows_ad(a.id) and a.is_active and (a.starts_at is null or a.starts_at<=now()) and (a.ends_at is null or a.ends_at>now())) then return; end if;
 -- A rotating digest limits linkage between days; no IP address is stored here.
 v_device_key := md5(p_installation_id::text || ':' || (now() at time zone 'UTC')::date::text);
 v_previous_device_key := md5(p_installation_id::text || ':' || ((now() at time zone 'UTC')::date - 1)::text);
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_installation_id::text,0));
 select count(*), count(distinct ad_id) into recent_count,recent_ads from app_private.ad_click_attempts a where a.device_key in (v_device_key,v_previous_device_key) and a.created_at > now()-interval '10 seconds';
 -- Excessive requests are dropped rather than creating unlimited rows for this identifier.
 if (select count(*) from app_private.ad_click_attempts a where a.device_key in (v_device_key,v_previous_device_key) and a.created_at > now()-interval '1 minute') >= 60 then return; end if;
 select exists(select 1 from app_private.ad_click_attempts a where a.device_key in (v_device_key,v_previous_device_key) and a.ad_id=p_ad_id and a.created_at > now()-interval '1 minute') into same_ad;
 classification := case when same_ad then 'repeat' when recent_count>=4 or recent_ads>=4 then 'suspicious' else 'candidate' end;
 insert into app_private.ad_click_attempts(device_key,ad_id) values(v_device_key,p_ad_id);
 insert into public.ad_events(ad_id,event_type,click_classification) values(p_ad_id,'click',classification);
 -- Incremental cleanup occurs during activity; it is not a scheduled retention guarantee.
 delete from app_private.ad_click_attempts where id in (select id from app_private.ad_click_attempts where created_at < now()-interval '24 hours' order by created_at limit 100);
end;
$$;

create or replace function app_private.record_ad_events(p_ids bigint[], p_event text) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if p_event not in ('loaded','click') or p_event is null or coalesce(cardinality(p_ids),0) not between 1 and 50 then
   raise exception 'invalid event';
 end if;
 insert into public.ad_events(ad_id,event_type)
 select distinct a.id,p_event from public.sim_ads a
 where a.id = any(p_ids) and app_private.advertiser_allows_ad(a.id) and a.is_active and (a.starts_at is null or a.starts_at <= now()) and (a.ends_at is null or a.ends_at > now());
end;
$$;
