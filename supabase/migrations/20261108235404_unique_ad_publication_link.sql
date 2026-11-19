create unique index advertiser_drafts_one_publication on public.advertiser_drafts(published_ad_id) where published_ad_id is not null;
