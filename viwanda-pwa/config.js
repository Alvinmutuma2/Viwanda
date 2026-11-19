/* Viwanda config — fill these in, then redeploy.
   Empty = DEMO mode (nothing real happens, numbers are illustrative).
   Leave idDomain-style values alone once live users exist. */
window.VIWANDA_CFG = {
  supabaseUrl: "",                 // your Polaris Supabase URL, e.g. https://xxxx.supabase.co
  supabaseKey: "",                 // anon / publishable key (sb_publishable_...)
  paybill:     "",                 // M-Pesa paybill or till that collects listing fees
  listingFee:  1500,               // KES / month per maker listing
  adminPhone:  "0759610468",       // who confirms manual payments (the WAASP admin)
  appUrl:      ""                  // this app's URL (for the install + share), optional
};
