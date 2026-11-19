create or replace function app_private.record_checked_click(p_ad_id bigint,p_installation_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_device_key text; v_previous_device_key text; recent_count integer; recent_ads integer; same_ad boolean; classification text;
begin
 if p_ad_id is null or p_ad_id <= 0 or p_installation_id is null then raise exception 'invalid click'; end if;
 if not exists (select 1 from public.sim_ads a where a.id=p_ad_id and a.is_active and (a.starts_at is null or a.starts_at<=now()) and (a.ends_at is null or a.ends_at>now())) then return; end if;
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
