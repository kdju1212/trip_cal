-- DRAFT ONLY: not applied or verified. Requires review and concurrency tests.
-- Append-only corrections. Actual paid billing remains disabled separately.
alter table public.ad_wallet_entries drop constraint ad_wallet_entries_kind_check;
alter table public.ad_wallet_entries add constraint ad_wallet_entries_kind_check
  check (kind in ('credit','debit','refund','credit_reversal'));
alter table public.ad_wallet_entries add column related_entry_id uuid references public.ad_wallet_entries(id);
drop index public.ad_wallet_entries_one_refund_per_click;
create unique index ad_wallet_one_credit_reversal on public.ad_wallet_entries(related_entry_id)
  where kind='credit_reversal';

create function app_private.partial_ad_click_refund(p_debit_id uuid,p_amount bigint,p_request_id uuid,p_reason text) returns text
language plpgsql security definer set search_path='' as $$
declare d public.ad_wallet_entries%rowtype; previous public.ad_wallet_entries%rowtype; refunded bigint; balance bigint;
begin
 if (select auth.uid()) is null or not app_private.is_ad_admin() or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception '2단계 인증된 관리자 권한이 필요합니다.' using errcode='42501'; end if;
 if p_debit_id is null or p_request_id is null or p_amount is null or p_amount<1 or char_length(trim(coalesce(p_reason,''))) not between 3 and 100 then raise exception '환불 내용을 확인해 주세요.'; end if;
 select * into d from public.ad_wallet_entries where id=p_debit_id and kind='debit' for update;
 if not found or d.click_event_id is null then raise exception '차감 내역을 찾을 수 없습니다.'; end if;
 select * into previous from public.ad_wallet_entries where reference_id=p_request_id;
 if found then
   if previous.kind='refund' and previous.related_entry_id=d.id and previous.amount_krw=p_amount and previous.owner_id=d.owner_id then return 'already_processed'; end if;
   raise exception '이미 사용된 요청 번호입니다.';
 end if;
 select coalesce(sum(amount_krw),0) into refunded from public.ad_wallet_entries where kind='refund' and click_event_id=d.click_event_id;
 if p_amount>d.amount_krw-refunded then raise exception '남은 환불 가능 금액을 초과했습니다.'; end if;
 select balance_krw into balance from public.ad_wallets where owner_id=d.owner_id for update;
 if not found then raise exception '광고주 잔액을 찾을 수 없습니다.'; end if;
 if balance+p_amount>1000000000000 then raise exception '잔액 한도를 초과합니다.'; end if;
 insert into public.ad_wallet_entries(owner_id,kind,amount_krw,reference_id,actor_id,note,campaign_id,group_id,draft_id,click_event_id,billing_day,related_entry_id)
 values(d.owner_id,'refund',p_amount,p_request_id,(select auth.uid()),trim(p_reason),d.campaign_id,d.group_id,d.draft_id,d.click_event_id,d.billing_day,d.id);
 update public.ad_wallets set balance_krw=balance_krw+p_amount,updated_at=now() where owner_id=d.owner_id;
 return 'refunded';
end $$;
revoke all on function app_private.partial_ad_click_refund(uuid,bigint,uuid,text) from public,anon,authenticated;
grant execute on function app_private.partial_ad_click_refund(uuid,bigint,uuid,text) to authenticated;
create function public.partial_ad_click_refund(p_debit_id uuid,p_amount bigint,p_request_id uuid,p_reason text) returns text
language sql security invoker set search_path='' as $$ select app_private.partial_ad_click_refund(p_debit_id,p_amount,p_request_id,p_reason); $$;
revoke all on function public.partial_ad_click_refund(uuid,bigint,uuid,text) from public,anon,authenticated;
grant execute on function public.partial_ad_click_refund(uuid,bigint,uuid,text) to authenticated;

create function app_private.reverse_ad_topup(p_credit_id uuid,p_request_id uuid,p_reason text) returns text
language plpgsql security definer set search_path='' as $$
declare c public.ad_wallet_entries%rowtype; previous public.ad_wallet_entries%rowtype; balance bigint;
begin
 if (select auth.uid()) is null or not app_private.is_ad_admin() or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception '2단계 인증된 관리자 권한이 필요합니다.' using errcode='42501'; end if;
 if p_credit_id is null or p_request_id is null or char_length(trim(coalesce(p_reason,''))) not between 3 and 100 then raise exception '취소 내용을 확인해 주세요.'; end if;
 select * into c from public.ad_wallet_entries where id=p_credit_id and kind='credit' for update;
 if not found then raise exception '충전 내역을 찾을 수 없습니다.'; end if;
 select * into previous from public.ad_wallet_entries where reference_id=p_request_id;
 if found then
   if previous.kind='credit_reversal' and previous.related_entry_id=c.id and previous.owner_id=c.owner_id then return 'already_processed'; end if;
   raise exception '이미 사용된 요청 번호입니다.';
 end if;
 if exists(select 1 from public.ad_wallet_entries where kind='credit_reversal' and related_entry_id=c.id) then return 'already_reversed'; end if;
 select balance_krw into balance from public.ad_wallets where owner_id=c.owner_id for update;
 if not found or balance<c.amount_krw then raise exception '잔액이 부족하여 충전을 취소할 수 없습니다.'; end if;
 insert into public.ad_wallet_entries(owner_id,kind,amount_krw,reference_id,actor_id,note,related_entry_id)
 values(c.owner_id,'credit_reversal',c.amount_krw,p_request_id,(select auth.uid()),trim(p_reason),c.id);
 update public.ad_wallets set balance_krw=balance_krw-c.amount_krw,updated_at=now() where owner_id=c.owner_id;
 return 'reversed';
end $$;
revoke all on function app_private.reverse_ad_topup(uuid,uuid,text) from public,anon,authenticated;
grant execute on function app_private.reverse_ad_topup(uuid,uuid,text) to authenticated;
create function public.reverse_ad_topup(p_credit_id uuid,p_request_id uuid,p_reason text) returns text
language sql security invoker set search_path='' as $$ select app_private.reverse_ad_topup(p_credit_id,p_request_id,p_reason); $$;
revoke all on function public.reverse_ad_topup(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.reverse_ad_topup(uuid,uuid,text) to authenticated;

create function app_private.list_ad_corrections() returns table(entry_id uuid,kind text,email text,amount_krw bigint,remaining_krw bigint,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if (select auth.uid()) is null or not app_private.is_ad_admin() or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception '2단계 인증된 관리자 권한이 필요합니다.' using errcode='42501'; end if;
 return query select e.id,e.kind,u.email::text,e.amount_krw,
   case when e.kind='debit' then e.amount_krw-coalesce((select sum(r.amount_krw) from public.ad_wallet_entries r where r.kind='refund' and r.click_event_id=e.click_event_id),0)::bigint
        when exists(select 1 from public.ad_wallet_entries r where r.kind='credit_reversal' and r.related_entry_id=e.id) then 0::bigint else e.amount_krw end,
   e.created_at
 from public.ad_wallet_entries e join auth.users u on u.id=e.owner_id
 where e.kind='credit' or (e.kind='debit' and e.click_event_id is not null)
 order by e.created_at desc,e.id desc limit 100;
end $$;
revoke all on function app_private.list_ad_corrections() from public,anon,authenticated;
grant execute on function app_private.list_ad_corrections() to authenticated;
create function public.list_ad_corrections() returns table(entry_id uuid,kind text,email text,amount_krw bigint,remaining_krw bigint,created_at timestamptz)
language sql stable security invoker set search_path='' as $$ select * from app_private.list_ad_corrections(); $$;
revoke all on function public.list_ad_corrections() from public,anon,authenticated;
grant execute on function public.list_ad_corrections() to authenticated;
