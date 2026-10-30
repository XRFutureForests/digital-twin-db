// Copy to config.js and fill in. config.js is gitignored, like docker/.env and
// web/jobs/config.js -- same key, same reason: the anon key is public by design
// (RLS is what protects the data) but it is this deployment's key, and this
// repo is mirrored publicly.
//
//   grep ANON_KEY docker/.env
window.DFTDB = {
  // The API, relative to this site. On dt.unr.uni-freiburg.de nginx proxies
  // Kong at /db/ on 443, so the default is right there.
  apiBase: "/db",

  // ANON_KEY from docker/.env.
  anonKey: "",

  // Who people write to when their team has no curator yet.
  contact: "",
};
