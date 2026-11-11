-- Advertisers submit drafts for manual review; publication is a separate table.
create table public.advertiser_drafts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  merchant_name text not null check (char_length(trim(merchant_name)) between 1 and 80),
  title text not null check (char_length(trim(title)) between 1 and 60),
  description text not null check (char_length(trim(description)) between 1 and 80 and description !~ E'[\\n\\r]'),
  sim_type text not null check (sim_type in ('sim', 'esim')),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  duration_days integer not null check (duration_days between 1 and 365),
  price_krw integer check (price_krw >= 0),
  image_path text not null check (image_path like owner_id::text || '/%'),
  purchase_url text not null check (purchase_url ~* '^https://'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.advertiser_drafts enable row level security;
revoke all on public.advertiser_drafts from anon, authenticated;
grant select, insert, update, delete on public.advertiser_drafts to authenticated;
create policy "advertisers read own drafts" on public.advertiser_drafts for select to authenticated using (owner_id = (select auth.uid()));
create policy "advertisers insert own drafts" on public.advertiser_drafts for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "advertisers edit own drafts" on public.advertiser_drafts for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "advertisers delete own drafts" on public.advertiser_drafts for delete to authenticated using (owner_id = (select auth.uid()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ad-draft-images', 'ad-draft-images', false, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
create policy "advertisers upload own ad images" on storage.objects for insert to authenticated
  with check (bucket_id = 'ad-draft-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "advertisers delete own ad images" on storage.objects for delete to authenticated
  using (bucket_id = 'ad-draft-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
