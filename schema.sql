-- ============================================================
-- VIWANDA backend — run in your Polaris Supabase (SQL editor).
-- The native-brand marketplace: rich maker profiles, discoverability,
-- outcome-weighted ranking, per-maker conversion (new shops reached),
-- and a PAYMENT-RAIL-AGNOSTIC auto-lock. Reuses Polaris `shops`.
-- ============================================================

-- 1) MAKER LISTINGS -------------------------------------------------
create table if not exists listings (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,          -- brand / company
  category     text,                   -- Oils & Fats, Flour & Grains, ...
  products     text,                   -- what they sell
  price_from   int,
  unit         text,
  coverage     text,                   -- where they deliver (location)
  website      text,
  instagram    text,
  facebook     text,
  tiktok       text,
  whatsapp     text,                   -- the direct line (discoverability)
  phone        text,                   -- owner / pays
  active       boolean not null default false,
  paid_through timestamptz,            -- "verified-paid until" — the ONLY gate
  created_at   timestamptz default now()
);
alter table listings enable row level security;

-- ============================================================
-- THE AUTO-LOCK ALGORITHM (rail-agnostic, zero-infra)
-- Visibility depends on ONE thing: paid_through in the future.
-- * Unlock: ANY confirmed payment (manual M-Pesa match, cash, bank,
--   future STK) sets paid_through = now()+30d. Viwanda never calls a
--   payment provider — it only reads this timestamp. Not bound to Daraja
--   or anyone.
-- * Lock: evaluated AT READ TIME (now() > paid_through) — so expiry is
--   automatic with no cron, no scheduler, no job. A lapsed maker simply
--   stops appearing the instant the clock passes paid_through.
-- * No one wrongly cut off: you confirm a renewal before expiry; the
--   countdown warns the maker; paid_through only ever moves forward.
-- ============================================================
drop policy if exists "public reads live listings" on listings;
create policy "public reads live listings"
  on listings for select
  using (active = true and paid_through is not null and paid_through > now());

-- 2) PAYMENTS (collected by any rail; you confirm the match) ---------
create table if not exists payments (
  id         uuid primary key default gen_random_uuid(),
  phone text, brand_name text, category text, products text, coverage text,
  website text, instagram text, facebook text, tiktok text, whatsapp text,
  price_from int, unit text,
  mpesa_code text, amount int default 1500,
  status text default 'pending',       -- pending | confirmed | rejected
  created_at timestamptz default now()
);
alter table payments enable row level security;
create policy "anon submit pending payment"
  on payments for insert with check (status = 'pending');

-- 3) EVENTS → the data that rates everything ------------------------
-- shop_ref lets us count DISTINCT shops reached (= new customers)
create table if not exists events (
  id         bigint generated always as identity primary key,
  listing_id uuid,
  shop_ref   text,                     -- which shop (phone/id), for new-customer count
  kind       text,                     -- view | connect | order
  created_at timestamptz default now()
);
alter table events enable row level security;
create policy "anon log events"
  on events for insert with check (kind in ('view','connect','order'));

-- per-maker conversion: the metric that proves the KES 1,500 is worth it
create or replace function listing_outcomes(l uuid)
returns table(views int, connects int, orders int, new_shops int)
language sql security definer set search_path = public as $$
  select count(*) filter (where kind='view')::int,
         count(*) filter (where kind='connect')::int,
         count(*) filter (where kind='order')::int,
         count(distinct shop_ref) filter (where kind in ('connect','order'))::int
  from events where listing_id = l;
$$;
grant execute on function listing_outcomes(uuid) to anon;

-- 4) DISCOVERY + OUTCOME-WEIGHTED RANK (FindRight formula, not spend) -
-- One read returns ONLY live (paid, unexpired) makers, each with a rank
-- earned from outcomes + response + profile quality + recency.
create or replace view listings_ranked as
select l.id, l.name, l.category, l.products, l.price_from, l.unit, l.coverage,
       l.website, l.instagram, l.facebook, l.tiktok, l.whatsapp, l.paid_through,
       coalesce(e.views,0)   as views,
       coalesce(e.connects,0) as connects,
       coalesce(e.orders,0)   as orders,
       coalesce(e.new_shops,0) as new_shops,
       round(
         coalesce(e.connects,0)*3.0           -- outcomes (chats)   30%
       + coalesce(e.orders,0)*3.0             -- outcomes (orders)  30%
       + (case when l.website  is not null then 1 else 0 end
        + case when l.whatsapp is not null then 1 else 0 end
        + case when l.products is not null then 1 else 0 end
        + case when l.coverage is not null then 1 else 0 end)*2.5  -- profile 10%
       + greatest(0, 10 - extract(day from now()-l.created_at))*1.0 -- recency 10%
       ) as rank_score
from listings l
left join (
  select listing_id,
    count(*) filter (where kind='view') views,
    count(*) filter (where kind='connect') connects,
    count(*) filter (where kind='order') orders,
    count(distinct shop_ref) filter (where kind in ('connect','order')) new_shops
  from events group by listing_id
) e on e.listing_id = l.id
where l.active and l.paid_through is not null and l.paid_through > now();
grant select on listings_ranked to anon;

-- 5) LIVE COUNTS (safe: numbers only) -------------------------------
create or replace function public_shop_count()
returns int language sql security definer set search_path = public as $$
  select count(*)::int from shops; $$;
grant execute on function public_shop_count() to anon;

-- honest platform health (counts only) — for your owner view
create or replace function platform_stats()
returns table(live_makers int, lapsed_makers int)
language sql security definer set search_path = public as $$
  select
    count(*) filter (where active and paid_through > now())::int,
    count(*) filter (where paid_through is not null and paid_through <= now())::int
  from listings; $$;
grant execute on function platform_stats() to anon;

-- 6) ADMIN CONFIRM — run with SERVICE ROLE / SQL editor (never browser)
-- This is the rail-agnostic unlock: call it the moment you've matched a
-- payment, from ANY source. It just extends paid_through.
create or replace function confirm_payment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare pr payments;
begin
  select * into pr from payments where id = p_id and status='pending';
  if pr.id is null then raise exception 'no pending payment %', p_id; end if;
  update payments set status='confirmed' where id = p_id;
  insert into listings(name,category,products,price_from,unit,coverage,website,
                       instagram,facebook,tiktok,whatsapp,phone,active,paid_through)
  values (pr.brand_name,pr.category,pr.products,pr.price_from,pr.unit,pr.coverage,
          pr.website,pr.instagram,pr.facebook,pr.tiktok,pr.whatsapp,pr.phone,
          true, now()+interval '30 days');
end; $$;
-- RENEW an existing maker instead:  update listings set paid_through = now()+interval '30 days' where id = '<listing>';
