// Shared plumbing for the portal pages: config, the signed-in session, API
// calls, and the top bar. No build step, no dependencies -- the same rule as
// web/jobs/, for the same reason: nginx serves these files as they are.
//
// The session lives under the same sessionStorage key the job page uses, so
// signing in on either one signs you in on both (same origin, same tab).
(function () {
  "use strict";

  var cfg = window.DFTDB || {};
  var API = (cfg.apiBase || "/db").replace(/\/$/, "");
  var TOKEN_KEY = "dftdb.session";
  var session = null;

  try {
    var raw = sessionStorage.getItem(TOKEN_KEY);
    if (raw) session = JSON.parse(raw);
  } catch (err) { session = null; }

  function saveSession(s) {
    session = s;
    try {
      if (s) sessionStorage.setItem(TOKEN_KEY, JSON.stringify(s));
      else sessionStorage.removeItem(TOKEN_KEY);
    } catch (err) { /* private mode: the session just will not survive a reload */ }
  }

  function claims() {
    if (!session) return {};
    try {
      return JSON.parse(atob(session.access_token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    } catch (err) { return {}; }
  }

  // NULL = no role = read-only. The tiers are cumulative: admin > curator >
  // contributor, matching shared.is_curator() / is_contributor().
  function role() { var c = claims(); return (c.app_metadata && c.app_metadata.role) || null; }
  function atLeast(tier) {
    var order = { contributor: 1, curator: 2, admin: 3 };
    return (order[role()] || 0) >= order[tier];
  }

  // PostgREST and GoTrue disagree about which key carries the readable part,
  // and the account functions put the actionable half in `hint`.
  function errorText(body, res) {
    if (body) {
      var t = body.message || body.error_description || body.msg || body.details || body.error;
      if (t && body.hint && body.hint !== t) return t + " — " + body.hint;
      if (t) return t;
      if (body.hint) return body.hint;
    }
    return "HTTP " + res.status + " " + res.statusText;
  }

  async function authCall(path, body) {
    var res = await fetch(API + "/auth/v1/" + path, {
      method: "POST",
      headers: { "apikey": cfg.anonKey, "Content-Type": "application/json" },
      body: JSON.stringify(body)
    });
    var out = await res.json().catch(function () { return null; });
    if (!res.ok) throw new Error(errorText(out, res));
    return out;
  }

  async function signIn(email, password) {
    saveSession(await authCall("token?grant_type=password", { email: email, password: password }));
    return session;
  }

  function signOut() {
    if (session) {
      // Best effort: revoke the refresh token server-side too.
      fetch(API + "/auth/v1/logout", {
        method: "POST",
        headers: { "apikey": cfg.anonKey, "Authorization": "Bearer " + session.access_token }
      }).catch(function () {});
    }
    saveSession(null);
  }

  // Access tokens live JWT_EXPIRY (an hour). Entering a batch of field data can
  // take longer than that, so refresh shortly before expiry instead of letting
  // a save fail with 401 halfway through.
  async function fresh() {
    if (!session) return;
    var exp = session.expires_at || claims().exp || 0;
    if (exp - Date.now() / 1000 > 60) return;
    try {
      saveSession(await authCall("token?grant_type=refresh_token", { refresh_token: session.refresh_token }));
    } catch (err) {
      saveSession(null);
      throw new Error("Your session ended. Sign in again.");
    }
  }

  // opts: method, body, headers, raw (return the Response), auth (default true)
  async function api(path, opts) {
    opts = opts || {};
    if (opts.auth !== false) await fresh();
    var h = { "apikey": cfg.anonKey };
    if (opts.body !== undefined) h["Content-Type"] = "application/json";
    if (opts.auth !== false && session) h["Authorization"] = "Bearer " + session.access_token;
    Object.keys(opts.headers || {}).forEach(function (k) { h[k] = opts.headers[k]; });
    var res = await fetch(API + path, {
      method: opts.method || "GET",
      headers: h,
      body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined
    });
    if (opts.raw && res.ok) return res;
    var text = await res.text();
    var body = null;
    if (text) { try { body = JSON.parse(text); } catch (err) { body = { message: text }; } }
    if (!res.ok) {
      var e = new Error(errorText(body, res));
      e.status = res.status;
      throw e;
    }
    return body;
  }

  async function updateUser(body) {
    await fresh();
    var res = await fetch(API + "/auth/v1/user", {
      method: "PUT",
      headers: { "apikey": cfg.anonKey, "Authorization": "Bearer " + session.access_token,
                 "Content-Type": "application/json" },
      body: JSON.stringify(body)
    });
    var out = await res.json().catch(function () { return null; });
    if (!res.ok) throw new Error(errorText(out, res));
    // The current access token still carries the old user_metadata; refresh
    // so the "change your password" banner goes away immediately.
    saveSession(await authCall("token?grant_type=refresh_token", { refresh_token: session.refresh_token }));
    return out;
  }

  /* ---------- small DOM helpers ---------- */

  function el(tag, attrs, children) {
    var n = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "text") n.textContent = attrs[k];
      else if (k === "class") n.className = attrs[k];
      else if (k.slice(0, 2) === "on") n.addEventListener(k.slice(2), attrs[k]);
      else if (attrs[k] !== undefined && attrs[k] !== null && attrs[k] !== false) n.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) {
      if (c === null || c === undefined) return;
      n.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
    });
    return n;
  }

  function message(where, kind, text) {
    var host = typeof where === "string" ? document.getElementById(where) : where;
    host.innerHTML = "";
    if (text) host.appendChild(el("div", { class: "msg " + kind, text: text }));
  }

  function roleLabel(r) { return r || "read-only"; }

  var PAGES = [
    ["/portal/", "Start"],
    ["/ecosense/", "Dashboards"],
    ["/portal/data/", "Data"],
    ["/jobs/", "Run models"],
    ["/portal/docs/", "Docs"],
    ["/portal/api/", "API"],
    ["/portal/account/", "Account"]
  ];

  function topbar(here) {
    var nav = el("nav", { class: "nav" }, PAGES.map(function (p) {
      return el("a", { href: p[0], class: p[0] === here ? "here" : null, text: p[1] });
    }));
    var who = el("span", { class: "whoami", id: "topWho" });
    var bar = el("div", { class: "topbar" }, [
      el("div", { class: "wrap" }, [el("a", { class: "brand", href: "/portal/", text: "Forest Digital Twin" }), nav, who])
    ]);
    document.body.insertBefore(bar, document.body.firstChild);
    refreshWho();

    if (!cfg.anonKey) {
      var warn = el("div", { class: "wrap" }, [el("div", {
        class: "msg err",
        text: "config.js is missing or has no anonKey. Copy web/portal/config.example.js to config.js and fill it in."
      })]);
      bar.parentNode.insertBefore(warn, bar.nextSibling);
    }
  }

  function refreshWho() {
    var who = document.getElementById("topWho");
    if (!who) return;
    who.innerHTML = "";
    if (session && session.user) {
      who.appendChild(document.createTextNode(session.user.email + " "));
      who.appendChild(el("span", { class: "badge" + (atLeast("contributor") ? " good" : ""), text: roleLabel(role()) }));
    } else {
      who.appendChild(el("a", { href: "/portal/account/", text: "Sign in" }));
    }
  }

  window.Portal = {
    cfg: cfg,
    get session() { return session; },
    claims: claims,
    role: role,
    roleLabel: roleLabel,
    atLeast: atLeast,
    signIn: signIn,
    signOut: signOut,
    api: api,
    updateUser: updateUser,
    el: el,
    message: message,
    topbar: topbar,
    refreshWho: refreshWho
  };
})();
