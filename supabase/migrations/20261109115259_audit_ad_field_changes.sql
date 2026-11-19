create or replace function app_private.audit_ad_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare before_row jsonb; after_row jsonb := to_jsonb(new); field text;
begin
 if tg_op='INSERT' then
   insert into app_private.ad_action_audit(entity_kind,entity_id,action,actor_id) values(tg_table_name,after_row->>'id','created',(select auth.uid()));
 else
   before_row:=to_jsonb(old);
   foreach field in array array['review_status','advertiser_enabled','deleted_at','is_active','daily_budget_krw','cpc_bid_krw','price_krw','name','merchant_name','title','description','purchase_url','image_path','sim_type','country_code','duration_days'] loop
     if before_row ? field and after_row ? field and (before_row->field) is distinct from (after_row->field) then
       insert into app_private.ad_action_audit(entity_kind,entity_id,action,actor_id,detail)
       values(tg_table_name,after_row->>'id',field,(select auth.uid()),case when field in ('review_status','advertiser_enabled','deleted_at','is_active','daily_budget_krw','cpc_bid_krw','price_krw','sim_type','country_code','duration_days') then jsonb_build_object('before',before_row->field,'after',after_row->field) else '{}'::jsonb end);
     end if;
   end loop;
 end if;
 return new;
end;
$$;
