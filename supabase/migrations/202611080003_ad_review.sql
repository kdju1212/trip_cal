-- Apply after 202611080001_sim_ads.sql and 202611080002_advertiser_drafts.sql.
-- Administrators are explicitly assigned by the project owner in the SQL Editor.
create table public.ad_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.ad_admins enable row level security;
revoke all on public.ad_admins from public, anon, authenticated;

create function public.is_ad_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.ad_admins where user_id = (select auth.uid()));
$$;
revoke all on function public.is_ad_admin() from public, anon;
grant execute on function public.is_ad_admin() to authenticated;

alter table public.advertiser_drafts
  add column review_status text not null default 'pending' check (review_status in ('pending','approved','rejected')),
  add column review_note text not null default '' check (char_length(review_note) <= 300),
  add column reviewed_at timestamptz,
  add column published_ad_id bigint references public.sim_ads(id) on delete set null;
-- Advertisers can submit and read, but cannot alter submissions after review begins.
revoke all on public.advertiser_drafts from anon, authenticated;
grant select on public.advertiser_drafts to authenticated;
grant insert (merchant_name, title, description, sim_type, country_code, duration_days, price_krw, image_path, purchase_url) on public.advertiser_drafts to authenticated;
drop policy "advertisers edit own drafts" on public.advertiser_drafts;
drop policy "advertisers delete own drafts" on public.advertiser_drafts;
create policy "admins read submissions" on public.advertiser_drafts for select to authenticated using ((select public.is_ad_admin()));

-- Approved images are public; unpublished source images stay private.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ad-published-images', 'ad-published-images', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
create policy "admins read draft images" on storage.objects for select to authenticated
  using (bucket_id = 'ad-draft-images' and (select public.is_ad_admin()));
create policy "admins publish images" on storage.objects for insert to authenticated
  with check (bucket_id = 'ad-published-images' and (select public.is_ad_admin()));
create policy "admins delete published images" on storage.objects for delete to authenticated
  using (bucket_id = 'ad-published-images' and (select public.is_ad_admin()));

create policy "admins read all ads" on public.sim_ads for select to authenticated using ((select public.is_ad_admin()));
grant select (is_active, starts_at, ends_at) on public.sim_ads to authenticated;

create function public.review_advertisement(p_draft_id uuid, p_approved boolean, p_image_path text default null, p_note text default '') returns void
language plpgsql security definer set search_path = '' as $$
declare d public.advertiser_drafts%rowtype; new_ad_id bigint; image_address text;
begin
  if not public.is_ad_admin() then raise exception '관리자 권한이 필요합니다.' using errcode = '42501'; end if;
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
    insert into public.sim_ads (merchant_name, title, description, sim_type, country_code, duration_days, price_krw, image_url, purchase_url, is_active)
    values (d.merchant_name, d.title, d.description, d.sim_type, d.country_code, d.duration_days, d.price_krw, image_address, d.purchase_url, true)
    returning id into new_ad_id;
    update public.advertiser_drafts set review_status='approved', reviewed_at=now(), review_note=coalesce(p_note,''), published_ad_id=new_ad_id where id=d.id;
  else
    if length(trim(coalesce(p_note, ''))) = 0 then raise exception '반려 사유를 입력해 주세요.'; end if;
    update public.advertiser_drafts set review_status='rejected', reviewed_at=now(), review_note=trim(p_note) where id=d.id;
  end if;
end;
$$;
revoke all on function public.review_advertisement(uuid, boolean, text, text) from public, anon;
grant execute on function public.review_advertisement(uuid, boolean, text, text) to authenticated;

create function public.set_ad_active(p_ad_id bigint, p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_ad_admin() then raise exception '관리자 권한이 필요합니다.' using errcode = '42501'; end if;
  if p_active is null then raise exception '노출 상태가 필요합니다.'; end if;
  update public.sim_ads set is_active = p_active, updated_at = now() where id = p_ad_id;
  if not found then raise exception '광고를 찾을 수 없습니다.'; end if;
end;
$$;
revoke all on function public.set_ad_active(bigint, boolean) from public, anon;
grant execute on function public.set_ad_active(bigint, boolean) to authenticated;
