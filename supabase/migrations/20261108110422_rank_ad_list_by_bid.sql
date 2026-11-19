-- Return only currently active public listings. Bid is used for ordering but is never returned.
create function app_private.list_ranked_sim_ads(p_country text,p_type text,p_days integer default null)
returns table(id bigint,merchant_name text,title text,description text,sim_type text,country_code text,duration_days integer,price_krw integer,image_url text,purchase_url text,priority integer,updated_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select a.id,a.merchant_name,a.title,a.description,a.sim_type,a.country_code,a.duration_days,a.price_krw,a.image_url,a.purchase_url,a.priority,a.updated_at
  from public.sim_ads a
  left join lateral (select max(g.cpc_bid_krw) as bid from public.advertiser_drafts d join public.ad_groups g on g.id=d.group_id and g.owner_id=d.owner_id where d.published_ad_id=a.id and d.review_status='approved') rank_data on true
  where p_country ~ '^[A-Z]{2}$' and p_type in ('sim','esim') and (p_days is null or p_days between 1 and 365)
    and a.country_code=p_country and a.sim_type=p_type and (p_days is null or a.duration_days=p_days)
    and a.is_active and (a.starts_at is null or a.starts_at<=now()) and (a.ends_at is null or a.ends_at>now())
  order by coalesce(rank_data.bid,0) desc,a.priority desc,a.id desc limit 50;
$$;
revoke all on function app_private.list_ranked_sim_ads(text,text,integer) from public,anon,authenticated;
grant execute on function app_private.list_ranked_sim_ads(text,text,integer) to anon,authenticated;
create function public.list_ranked_sim_ads(p_country text,p_type text,p_days integer default null)
returns table(id bigint,merchant_name text,title text,description text,sim_type text,country_code text,duration_days integer,price_krw integer,image_url text,purchase_url text,priority integer,updated_at timestamptz)
language sql stable security invoker set search_path = '' as $$ select * from app_private.list_ranked_sim_ads(p_country,p_type,p_days); $$;
revoke all on function public.list_ranked_sim_ads(text,text,integer) from public,anon,authenticated;
grant execute on function public.list_ranked_sim_ads(text,text,integer) to anon,authenticated;
