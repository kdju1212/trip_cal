grant update(name, daily_budget_krw) on public.ad_campaigns to authenticated;
create policy "campaign owner update" on public.ad_campaigns for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
grant update(name, sim_type, country_code, duration_days, cpc_bid_krw) on public.ad_groups to authenticated;
create policy "group owner update" on public.ad_groups for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create function app_private.edit_ad_creative(p_id uuid, p_merchant text, p_title text, p_description text, p_price integer, p_url text, p_image_path text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare d public.advertiser_drafts%rowtype; g public.ad_groups%rowtype;
begin
 if (select auth.uid()) is null then raise exception '로그인이 필요합니다.' using errcode='42501'; end if;
 select * into d from public.advertiser_drafts where id=p_id and owner_id=(select auth.uid()) for update;
 if not found then raise exception '소재를 찾을 수 없습니다.'; end if;
 if p_image_path is not null and (p_image_path not like d.owner_id::text || '/%' or not exists(select 1 from storage.objects where bucket_id='ad-draft-images' and name=p_image_path)) then raise exception '이미지를 확인해 주세요.'; end if;
 if d.group_id is not null then select * into g from public.ad_groups where id=d.group_id and owner_id=d.owner_id; end if;
 if d.published_ad_id is not null then update public.sim_ads set is_active=false, updated_at=now() where id=d.published_ad_id; end if;
 update public.advertiser_drafts set merchant_name=p_merchant, title=p_title, description=p_description, price_krw=p_price, purchase_url=p_url,
 image_path=coalesce(p_image_path,d.image_path), sim_type=coalesce(g.sim_type,d.sim_type), country_code=coalesce(g.country_code,d.country_code), duration_days=coalesce(g.duration_days,d.duration_days),
 review_status='pending', review_note='', reviewed_at=null, updated_at=now() where id=d.id;
end;
$$;
revoke all on function app_private.edit_ad_creative(uuid,text,text,text,integer,text,text) from public, anon, authenticated;
grant execute on function app_private.edit_ad_creative(uuid,text,text,text,integer,text,text) to authenticated;
create function public.edit_ad_creative(p_id uuid, p_merchant text, p_title text, p_description text, p_price integer, p_url text, p_image_path text default null) returns void
language sql security invoker set search_path = '' as $$ select app_private.edit_ad_creative(p_id,p_merchant,p_title,p_description,p_price,p_url,p_image_path); $$;
revoke all on function public.edit_ad_creative(uuid,text,text,text,integer,text,text) from public, anon, authenticated;
grant execute on function public.edit_ad_creative(uuid,text,text,text,integer,text,text) to authenticated;
create or replace function app_private.review_advertisement(p_draft_id uuid, p_approved boolean, p_image_path text default null, p_note text default '') returns void
language plpgsql security definer set search_path = '' as $$
declare d public.advertiser_drafts%rowtype; new_ad_id bigint; image_address text;
begin
  if (select auth.uid()) is null or not app_private.is_ad_admin() then raise exception '관리자 권한이 필요합니다.' using errcode = '42501'; end if;
  select * into d from public.advertiser_drafts where id = p_draft_id for update;
  if not found or d.review_status <> 'pending' then raise exception '이미 검수되었거나 찾을 수 없는 광고입니다.'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception '검수 의견이 너무 깁니다.'; end if;
  if p_approved is null then raise exception '승인 여부가 필요합니다.'; end if;
  if p_approved then
    if p_image_path is null or p_image_path !~ '^[a-zA-Z0-9/_-]+\.(jpg|png|webp)$' or
       not exists (select 1 from storage.objects where bucket_id = 'ad-published-images' and name = p_image_path) then
      raise exception '공개 이미지가 필요합니다.';
    end if;
    image_address := 'https://jpgtswemhxqlbhsondve.supabase.co/storage/v1/object/public/ad-published-images/' || p_image_path;
    if d.published_ad_id is null then
      insert into public.sim_ads (merchant_name,title,description,sim_type,country_code,duration_days,price_krw,image_url,purchase_url,is_active)
      values (d.merchant_name,d.title,d.description,d.sim_type,d.country_code,d.duration_days,d.price_krw,image_address,d.purchase_url,true) returning id into new_ad_id;
    else
      update public.sim_ads set merchant_name=d.merchant_name,title=d.title,description=d.description,sim_type=d.sim_type,country_code=d.country_code,duration_days=d.duration_days,price_krw=d.price_krw,image_url=image_address,purchase_url=d.purchase_url,is_active=true,updated_at=now() where id=d.published_ad_id returning id into new_ad_id;
      if not found then raise exception '기존 광고를 찾을 수 없습니다.'; end if;
    end if;
    update public.advertiser_drafts set review_status='approved',reviewed_at=now(),review_note=coalesce(p_note,''),published_ad_id=new_ad_id where id=d.id;
  else
    if length(trim(coalesce(p_note,''))) = 0 then raise exception '반려 사유를 입력해 주세요.'; end if;
    update public.advertiser_drafts set review_status='rejected',reviewed_at=now(),review_note=trim(p_note) where id=d.id;
  end if;
end;
$$;
