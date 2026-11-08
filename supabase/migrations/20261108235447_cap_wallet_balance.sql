alter table public.ad_wallets add constraint ad_wallet_balance_limit check (balance_krw <= 1000000000000);
