// Copy to config.js and fill in. config.js is gitignored, like docker/.env.
//
// The anon key is public by design — Unreal ships with it, and RLS is what
// actually protects the data — but it is still this deployment's key, so it is
// not committed to a repo that is mirrored publicly.
//
// Get it from digital-twin-db/docker/.env on the host that serves this page:
//   grep ANON_KEY docker/.env
window.DFTDB = {
  // Where the API lives, relative to this page or absolute. On
  // dt.unr.uni-freiburg.de nginx proxies Kong at /db/ on 443, because a campus
  // client-subnet ACL blocks every inbound port but 22 and 443 — so the
  // default below is the right answer there and the page needs no origin.
  apiBase: "/db",

  // ANON_KEY from docker/.env.
  anonKey: "",
};
