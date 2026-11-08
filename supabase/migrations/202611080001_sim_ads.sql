-- Manage this table in the Supabase dashboard. Clients can only read active ads.
create table public.sim_ads (
  id bigint generated always as identity primary key,
  merchant_name text not null check (length(trim(merchant_name)) between 1 and 80),
  title text not null check (length(trim(title)) between 1 and 120),
  description text not null default '' check (length(description) <= 300),
  sim_type text not null check (sim_type in ('sim', 'esim')),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  duration_days integer not null check (duration_days between 1 and 365),
  price_krw integer check (price_krw >= 0),
  image_url text check (image_url is null or image_url ~* '^https://'),
  purchase_url text not null check (purchase_url ~* '^https://'),
  is_active boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  priority integer not null default 0,
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index sim_ads_listing on public.sim_ads (country_code, sim_type, duration_days, priority desc);
alter table public.sim_ads enable row level security;
revoke all on public.sim_ads from anon, authenticated;
grant select (id, merchant_name, title, description, sim_type, country_code, duration_days, price_krw, image_url, purchase_url, priority, updated_at) on public.sim_ads to anon, authenticated;
create policy "public reads currently active ads" on public.sim_ads for select to anon, authenticated
  using (is_active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));
