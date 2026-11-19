# Viwanda — the home for Kenya's makers (deploy like Polaris)

A PWA where Kenyan shops find the manufacturers (makers) behind the shelf,
makers get discovered on a KES 1,500/month listing, and banks finance the stock.
Rides on Polaris.

## What's inside
- Rich maker profiles: category, products, price, coverage, website, socials, WhatsApp
- Discovery: search + category browse + sort (popular / price)
- **Outcome-weighted rank** (FindRight formula) — rank is earned from real
  outcomes, never bought
- **New shops reached** — the one conversion stat that proves the KES 1,500 is worth it
- **Owner view** (top-right "owner") — honest platform health: paying makers,
  renewal rate, what the data says to improve. Feedback from data, not reviews.
- **Payment-agnostic auto-lock** (see below)
- Installable PWA (manifest, service worker, offline, icons)

## Files
`index.html` · `config.js` (edit) · `sw.js` · `manifest.webmanifest` · `icons/` ·
`schema.sql` (run once)

## Deploy (one step at a time, like Polaris)
1. Run `schema.sql` in your Polaris Supabase → SQL editor.
2. Edit `config.js`: Supabase URL + anon key, and your M-Pesa `paybill`.
3. Push the folder to a `Viwanda` GitHub Pages repo (relative paths — keep them).
4. Open it — the badge flips amber **demo** → green **live**.

## The auto-lock algorithm (no Daraja, no scheduler, no lock-in)
Visibility depends on exactly ONE field: `paid_through`.
- **A listing shows only while** `active AND paid_through > now()` — enforced by the
  database read policy, so it's checked on *every* read.
- **Unlock:** when you match a payment from ANY source (manual M-Pesa code, cash,
  bank, a future STK), you set `paid_through = now()+30 days`. Viwanda never calls
  a payment provider — it only reads the timestamp. You are not tied to Daraja or
  anyone.
- **Lock:** happens automatically at read time the instant the clock passes
  `paid_through`. No cron job, no background task — a lapsed maker simply stops
  appearing.
- **No one wrongly cut off:** `paid_through` only moves forward; the maker sees a
  countdown and renews before it passes. (Try it: list in demo, then
  "fast-forward to expiry" to watch the lock engage.)

## Listing a maker (the WAASP way)
1. Maker fills the form, pays your paybill KES 1,500, pastes the M-Pesa code.
2. App writes a **pending** payment.
3. You confirm: `select confirm_payment('<payment-id>');` → live for 30 days.
4. Renew = pay again, confirm again (or `update listings set paid_through = now()+interval '30 days'`).

## The plan
KES 1,500 × ~2,000 makers = **3M/month floor**. Featured + done-for-you (20k) tiers
and stock-loan origination compound on top. Polaris (free shops) + Viwanda (paid
makers + banks) = layer zero.
