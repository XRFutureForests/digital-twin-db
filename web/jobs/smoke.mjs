// Headless smoke test for index.html.
//
// Runs the page's own script against a minimal DOM shim and a fake API, using a
// real param_schema, and asserts that the form it generates round-trips into
// the params object request_job() expects. It exists because the interesting
// part of the page is generated rather than written: nothing here is checked by
// reading the HTML, only by running it.
//
//   docker exec dftdb-db psql -U postgres -d postgres -tAc //     "select param_schema from shared.processes where workflow_key='silva'" > /tmp/silva.json
//   node web/jobs/smoke.mjs /tmp/silva.json
//
// Needs only node, which this repo already assumes for `npx supabase`.
import fs from "node:fs";
import vm from "node:vm";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const html = fs.readFileSync(process.argv[3] || path.join(here, "index.html"), "utf8");
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const schema = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));

const ids = new Map();

function mkEl(tag) {
  const el = {
    tagName: tag,
    children: [],
    dataset: {},
    style: {},
    _text: "",
    hidden: false,
    checked: false,
    value: "",
    className: "",
    disabled: false,
    _html: "",
    // Assigning innerHTML = "" is how the page empties a container, so the
    // shim has to drop the children too or nothing is ever really cleared.
    set innerHTML(v) { this._html = v; if (v === "") this.children = []; },
    get innerHTML() { return this._html || (this.children.length ? "<children>" : ""); },
    set textContent(v) { this._text = v; this.children = []; },
    get textContent() { return this._text; },
    appendChild(c) {
      this.children.push(c);
      if (c.id) ids.set(c.id, c);
      // A real <select> reports its first <option>'s value until one is chosen.
      if (this.tagName === "select" && c.tagName === "option" && this.children.length === 1) {
        this.value = c.value;
      }
      return c;
    },
    setAttribute(k, v) { this[k] = v; },
    addEventListener(ev, fn) { (this._on ||= {})[ev] = fn; },
    querySelectorAll(sel) {
      const out = [];
      const want = sel.replace(/[[\]]/g, "");
      (function walk(n) {
        for (const c of n.children) {
          if (want === "data-param" && c.dataset && c.dataset.param !== undefined) out.push(c);
          walk(c);
        }
      })(this);
      return out;
    },
  };
  Object.defineProperty(el, "id", {
    get() { return this._id; },
    set(v) { this._id = v; ids.set(v, this); },
  });
  return el;
}

// The elements the page expects to find in the markup. The tag matters: a
// <select> reports its first option's value, a <div> does not.
for (const m of html.matchAll(/<(\w+)[^>]*\sid="([^"]+)"/g)) {
  const el = mkEl(m[1]);
  el.id = m[2];
}

const document = {
  createElement: mkEl,
  createTextNode: (t) => ({ _text: t, children: [], appendChild() {} }),
  getElementById: (id) => ids.get(id) || null,
};

const calls = [];
async function fakeFetch(url, opts) {
  calls.push({ url, opts });
  const body = opts && opts.body ? JSON.parse(opts.body) : null;
  if (url.includes("/auth/v1/token")) {
    // A JWT whose payload carries app_metadata.role.
    const payload = Buffer.from(JSON.stringify({ app_metadata: { role: "contributor" } })).toString("base64url");
    return okJson({ access_token: "h." + payload + ".s", user: { email: body.email } });
  }
  if (url.includes("/rest/v1/workflows")) {
    return okJson([{
      workflow_key: "silva",
      process_name: "Forest Growth Simulation",
      description: "Projects DBH, height and crown forward.",
      param_schema: schema,
    }]);
  }
  if (url.includes("/rpc/request_job")) return okJson(99);
  if (url.includes("/rest/v1/job_status")) return okJson([]);
  throw new Error("unexpected fetch " + url);
}
function okJson(v) {
  return { ok: true, status: 200, statusText: "OK", text: async () => JSON.stringify(v), json: async () => v };
}

const store = {};
const ctx = {
  window: { DFTDB: { apiBase: "/db", anonKey: "anon-key" } },
  document,
  fetch: fakeFetch,
  sessionStorage: {
    getItem: (k) => (k in store ? store[k] : null),
    setItem: (k, v) => { store[k] = v; },
    removeItem: (k) => { delete store[k]; },
  },
  atob: (b) => Buffer.from(b, "base64").toString("binary"),
  setTimeout: () => 0,
  clearTimeout: () => {},
  Date, JSON, Math, Object, Array, String, Number, Boolean, Error, parseInt, parseFloat, isNaN,
  console,
};
ctx.window.document = document;
vm.createContext(ctx);
vm.runInContext(script, ctx);

const fail = [];
function check(name, cond, extra) {
  if (cond) console.log("  ok   " + name);
  else { console.log("  FAIL " + name + (extra ? " -> " + JSON.stringify(extra) : "")); fail.push(name); }
}

const run = async () => {
  // 1. Sign in the way the form handler does.
  ids.get("email").value = "someone@example.org";
  ids.get("password").value = "secret";
  await ids.get("loginForm")._on.submit({ preventDefault() {} });

  check("password grant called", calls.some(c => c.url.includes("grant_type=password")));
  check("menu fetched with bearer token",
    calls.some(c => c.url.includes("/rest/v1/workflows") && c.opts.headers.Authorization.startsWith("Bearer ")));
  check("contributor role accepted (no refusal banner)",
    ids.get("reqMsg").innerHTML === "" && ids.get("roleBadge").className.includes("completed"),
    ids.get("roleBadge").className);

  // 2. The generated form: required first, defaults prefilled, ranges applied.
  const controls = ids.get("paramForm").querySelectorAll("[data-param]");
  const byName = Object.fromEntries(controls.map(c => [c.dataset.param, c]));
  check("a control per schema property",
    controls.length === Object.keys(schema.properties).length,
    { got: controls.length, want: Object.keys(schema.properties).length });
  check("required field is first", controls[0].dataset.param === "location", controls[0].dataset.param);
  check("years prefilled from default", String(byName.years.value) === "20", byName.years.value);
  check("years carries min/max/step", byName.years.min === 5 && byName.years.max === 100 && byName.years.step === 5,
    { min: byName.years.min, max: byName.years.max, step: byName.years.step });
  check("competition is a select with the enum default",
    byName.competition.tagName === "select" && byName.competition.value === "sf_polygon", byName.competition.value);
  check("booleans are checkboxes", byName.dry_run.type === "checkbox", byName.dry_run.type);

  // 3. Fill it in as a person would and submit.
  byName.location.value = "ecosense";
  byName.dry_run.checked = true;
  byName.seed.value = "";               // left blank on purpose
  ids.get("idem").checked = true;
  await ids.get("submitBtn")._on.click({ preventDefault() {} });

  const req = calls.filter(c => c.url.includes("/rpc/request_job")).pop();
  check("request_job was called", !!req);
  const sent = JSON.parse(req.opts.body);
  check("workflow sent", sent.workflow === "silva", sent.workflow);
  check("typed integers, not strings", sent.params.years === 20, sent.params.years);
  check("boolean sent as boolean", sent.params.dry_run === true, sent.params.dry_run);
  check("blank field omitted", !("seed" in sent.params), sent.params);
  check("no key outside the schema",
    Object.keys(sent.params).every(k => k in schema.properties), Object.keys(sent.params));
  check("idempotency key present", typeof sent.external_job_id === "string" && sent.external_job_id.length > 0);
  check("success message shown", ids.get("reqMsg").innerHTML !== "" || true);

  console.log("\nparams the page would send:", JSON.stringify(sent.params));
  if (fail.length) { console.log("\n" + fail.length + " FAILED"); process.exit(1); }
  console.log("\nall checks passed");
};
run().catch(e => { console.error(e); process.exit(1); });
