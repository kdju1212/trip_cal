-- One full refund per charged click. Audit rows and debits are retained.
create unique index ad_wallet_entries_one_refund_per_click on public.ad_wallet_entries(click_event_id) where kind='refund';
create function app_private.refund_ad_click(p_debit_id uuid,p_reason text) returns text
language plpgsql security definer set search_path='' as $$
declare d public.ad_wallet_entries%rowtype; w public.ad_wallets%rowtype;
begin
 if (select auth.uid()) is null or not app_private.is_ad_admin() or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception '2단계 인증된 관리자 권한이 필요합니다.' using errcode='42501'; end if;
 if p_debit_id is null or char_length(trim(coalesce(p_reason,''))) not between 3 and 100 then raise exception '환불 사유를 입력해 주세요.'; end if;
 select * into d from public.ad_wallet_entries where id=p_debit_id and kind='debit' for update;
 if not found or d.click_event_id is null then raise exception '차감 내역을 찾을 수 없습니다.'; end if;
 if exists(select 1 from public.ad_wallet_entries where kind='refund' and click_event_id=d.click_event_id) then return 'already_refunded'; end if;
 select * into w from public.ad_wallets where owner_id=d.owner_id for update;
 if not found then raise exception '광고주 잔액을 찾을 수 없습니다.'; end if;
 if w.balance_krw+d.amount_krw>1000000000000 then raise exception '잔액 한도를 초과하여 관리자 확인이 필요합니다.'; end if;
 insert into public.ad_wallet_entries(owner_id,kind,amount_krw,reference_id,actor_id,note,campaign_id,group_id,draft_id,click_event_id,billing_day)
 values(d.owner_id,'refund',d.amount_krw,gen_random_uuid(),(select auth.uid()),trim(p_reason),d.campaign_id,d.group_id,d.draft_id,d.click_event_id,d.billing_day);
 update public.ad_wallets set balance_krw=balance_krw+d.amount_krw,updated_at=now() where owner_id=d.owner_id;
 return 'refunded';
end;
$$;
revoke all on function app_private.refund_ad_click(uuid,text) from public,anon,authenticated;
grant execute on function app_private.refund_ad_click(uuid,text) to authenticated;
create function public.refund_ad_click(p_debit_id uuid,p_reason text) returns text
language sql security invoker set search_path='' as $$ select app_private.refund_ad_click(p_debit_id,p_reason); $$;
revoke all on function public.refund_ad_click(uuid,text) from public,anon,authenticated;
grant execute on function public.refund_ad_click(uuid,text) to authenticated;

create or replace function app_private.confirm_manual_ad_topup(p_owner uuid,p_amount bigint,p_reference uuid,p_note text) returns void
language plpgsql security definer set search_path='' as $$
declare existing public.ad_wallet_entries%rowtype;
begin
 if (select auth.uid()) is null or not app_private.is_ad_admin() then raise exception '관리자 권한이 필요합니다.' using errcode='42501'; end if;
 if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception '2단계 인증된 관리자 권한이 필요합니다.' using errcode='42501'; end if;
 if not coalesce((select enabled from app_private.ad_billing_settings where singleton),false) then raise exception '광고 과금은 아직 준비 중입니다.'; end if;
 if p_owner is null or p_reference is null or p_amount is null or p_amount<1 or p_amount>1000000000 or char_length(coalesce(p_note,''))>100 then raise exception '충전 내용을 확인해 주세요.'; end if;
 if not exists(select 1 from auth.users where id=p_owner) then raise exception '광고주 계정을 찾을 수 없습니다.'; end if;
 insert into public.ad_wallets(owner_id) values(p_owner) on conflict(owner_id) do nothing;
 perform 1 from public.ad_wallets where owner_id=p_owner for update;
 select * into existing from public.ad_wallet_entries where reference_id=p_reference;
 if found then
   if existing.owner_id=p_owner and existing.kind='credit' and existing.amount_krw=p_amount then return; end if;
   raise exception '이미 사용된 충전 요청 번호입니다.';
 end if;
 insert into public.ad_wallet_entries(owner_id,kind,amount_krw,reference_id,actor_id,note) values(p_owner,'credit',p_amount,p_reference,(select auth.uid()),coalesce(p_note,''));
 update public.ad_wallets set balance_krw=balance_krw+p_amount,updated_at=now() where owner_id=p_owner;
end;
$$;

create or replace function app_private.charge_verified_ad_click(p_event_id bigint) returns text
language plpgsql security definer set search_path='' as $$
declare e public.ad_events%rowtype; d public.advertiser_drafts%rowtype; g public.ad_groups%rowtype; c public.ad_campaigns%rowtype; w public.ad_wallets%rowtype; spent bigint; day_kst date;
begin
 if not coalesce((select enabled from app_private.ad_billing_settings where singleton),false) then raise exception '광고 과금은 아직 준비 중입니다.'; end if;
 select * into e from public.ad_events where id=p_event_id for update;
 if not found or e.event_type<>'click' or e.click_classification<>'candidate' or e.bid_at_click_krw is null then raise exception '청구 가능한 클릭을 찾을 수 없습니다.'; end if;
 if not exists(select 1 from app_private.verified_ad_clicks where event_id=e.id) then raise exception '클릭 검증이 필요합니다.' using errcode='42501'; end if;
 if exists(select 1 from public.ad_wallet_entries where kind='debit' and click_event_id=e.id) then return 'already_charged'; end if;
 select * into d from public.advertiser_drafts where published_ad_id=e.ad_id and review_status='approved' and deleted_at is null and advertiser_enabled for update;
 if not found or d.group_id is null then return 'not_eligible'; end if;
 select * into g from public.ad_groups where id=d.group_id and owner_id=d.owner_id and deleted_at is null and advertiser_enabled;
 if not found then return 'not_eligible'; end if;
 select * into c from public.ad_campaigns where id=g.campaign_id and owner_id=d.owner_id and deleted_at is null and advertiser_enabled for update;
 if not found or not exists(select 1 from public.sim_ads a where a.id=e.ad_id and a.is_active and (a.starts_at is null or a.starts_at<=now()) and (a.ends_at is null or a.ends_at>now())) then return 'not_eligible'; end if;
 if e.created_at < now()-interval '24 hours' or e.created_at>now() then return 'expired'; end if;
 day_kst := (e.created_at at time zone 'Asia/Seoul')::date;
 select coalesce(sum(case when kind='debit' then amount_krw when kind='refund' then -amount_krw else 0 end),0) into spent from public.ad_wallet_entries where kind in ('debit','refund') and campaign_id=c.id and billing_day=day_kst;
 if c.daily_budget_krw is not null and spent+e.bid_at_click_krw>c.daily_budget_krw then return 'budget_exhausted'; end if;
 if e.bid_at_click_krw=0 then return 'zero_bid'; end if;
 select * into w from public.ad_wallets where owner_id=d.owner_id for update;
 if not found or w.balance_krw<e.bid_at_click_krw then return 'insufficient_balance'; end if;
 insert into public.ad_wallet_entries(owner_id,kind,amount_krw,reference_id,campaign_id,group_id,draft_id,click_event_id,billing_day,note)
 values(d.owner_id,'debit',e.bid_at_click_krw,gen_random_uuid(),c.id,g.id,d.id,e.id,day_kst,'검증된 광고 클릭');
 update public.ad_wallets set balance_krw=balance_krw-e.bid_at_click_krw,updated_at=now() where owner_id=d.owner_id;
 return 'charged';
end;
$$;

-- When billing is eventually enabled, hide ads that cannot fund another click.
-- Paid mode remains disabled until a trusted verification service exists.
create or replace function app_private.advertiser_allows_ad(p_ad_id bigint) returns boolean
language sql stable security definer set search_path='' as $$
 select case
  when not exists(select 1 from public.advertiser_drafts d where d.published_ad_id=p_ad_id)
   then not coalesce((select enabled from app_private.ad_billing_settings where singleton),false)
  else exists(select 1 from public.advertiser_drafts d
   left join public.ad_groups g on g.id=d.group_id and g.owner_id=d.owner_id
   left join public.ad_campaigns c on c.id=g.campaign_id and c.owner_id=g.owner_id
   left join public.ad_wallets w on w.owner_id=d.owner_id
   where d.published_ad_id=p_ad_id and d.review_status='approved' and d.advertiser_enabled and d.deleted_at is null
    and (d.group_id is null or (g.id is not null and g.advertiser_enabled and g.deleted_at is null and c.id is not null and c.advertiser_enabled and c.deleted_at is null))
    and (not coalesce((select enabled from app_private.ad_billing_settings where singleton),false) or
      (g.id is not null and coalesce(w.balance_krw,0)>=g.cpc_bid_krw and
       (c.daily_budget_krw is null or coalesce((select sum(case when e.kind='debit' then e.amount_krw when e.kind='refund' then -e.amount_krw else 0 end) from public.ad_wallet_entries e where e.campaign_id=c.id and e.kind in ('debit','refund') and e.billing_day=(now() at time zone 'Asia/Seoul')::date),0)+g.cpc_bid_krw<=c.daily_budget_krw)))
  ) end;
$$;

create or replace function public.my_ad_costs(p_days integer default 30) returns table(draft_id uuid,cost_krw bigint)
language sql stable security invoker set search_path='' as $$
 select d.id,coalesce(sum(case when e.kind='debit' then e.amount_krw when e.kind='refund' then -e.amount_krw else 0 end),0)::bigint
 from public.advertiser_drafts d left join public.ad_wallet_entries e on e.draft_id=d.id and e.kind in ('debit','refund')
 and (p_days=0 or (e.billing_day >= (now() at time zone 'Asia/Seoul')::date-(p_days-1) and e.billing_day <= (now() at time zone 'Asia/Seoul')::date))
 where d.owner_id=(select auth.uid()) and p_days in (0,1,7,30) group by d.id;
$$;
