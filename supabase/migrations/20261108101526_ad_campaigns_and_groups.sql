create table public.ad_campaigns (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 name text not null check (char_length(trim(name)) between 1 and 80),
 daily_budget_krw bigint check (daily_budget_krw between 0 and 2147483647),
 created_at timestamptz not null default now(),
 unique(id, owner_id)
);
create table public.ad_groups (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 campaign_id uuid not null,
 name text not null check (char_length(trim(name)) between 1 and 80),
 sim_type text not null check (sim_type in ('sim','esim')),
 country_code text not null check (country_code ~ '^[A-Z]{2}$'),
 duration_days integer not null check (duration_days between 1 and 365),
 cpc_bid_krw integer not null check (cpc_bid_krw between 0 and 2147483647),
 created_at timestamptz not null default now(),
 unique(id, owner_id),
 foreign key(campaign_id, owner_id) references public.ad_campaigns(id, owner_id)
);
create index ad_campaigns_owner_idx on public.ad_campaigns(owner_id, created_at desc);
create index ad_groups_owner_campaign_idx on public.ad_groups(owner_id, campaign_id);
alter table public.ad_campaigns enable row level security;
alter table public.ad_groups enable row level security;
revoke all on public.ad_campaigns, public.ad_groups from public, anon, authenticated;
grant select on public.ad_campaigns, public.ad_groups to authenticated;
grant insert (name, daily_budget_krw) on public.ad_campaigns to authenticated;
grant insert (campaign_id, name, sim_type, country_code, duration_days, cpc_bid_krw) on public.ad_groups to authenticated;
create policy "campaigns owned or admin read" on public.ad_campaigns for select to authenticated using (owner_id = (select auth.uid()) or (select app_private.is_ad_admin()));
create policy "campaigns owner insert" on public.ad_campaigns for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "groups owned or admin read" on public.ad_groups for select to authenticated using (owner_id = (select auth.uid()) or (select app_private.is_ad_admin()));
create policy "groups owner insert" on public.ad_groups for insert to authenticated with check (owner_id = (select auth.uid()));
alter table public.advertiser_drafts add column group_id uuid;
alter table public.advertiser_drafts add constraint draft_group_owner_fk foreign key(group_id, owner_id) references public.ad_groups(id, owner_id);
create index advertiser_drafts_group_idx on public.advertiser_drafts(group_id);
grant insert (group_id) on public.advertiser_drafts to authenticated;
create policy "draft group settings consistent" on public.advertiser_drafts as restrictive for insert to authenticated with check (
 group_id is null or exists (select 1 from public.ad_groups g where g.id = advertiser_drafts.group_id and g.owner_id = advertiser_drafts.owner_id and g.sim_type = advertiser_drafts.sim_type and g.country_code = advertiser_drafts.country_code and g.duration_days = advertiser_drafts.duration_days)
);
