// ── Auth ──

export function tokensMatch(presented, secret) {
  if (!presented || !secret || presented.length !== secret.length) return false;
  let diff = 0;
  for (let i = 0; i < presented.length; i++) diff |= presented.charCodeAt(i) ^ secret.charCodeAt(i);
  return diff === 0;
}

// The presented token, from (in order) ?token=, the dash cookie, or a Bearer header.
export function presentedToken(request) {
  const url = new URL(request.url);
  const fromQuery = url.searchParams.get('token');
  if (fromQuery) return fromQuery;
  const cookie = (request.headers.get('cookie') ?? '')
    .split(';').map((c) => c.trim()).find((c) => c.startsWith('dash='));
  if (cookie) return decodeURIComponent(cookie.slice('dash='.length));
  const auth = request.headers.get('authorization') ?? '';
  return auth.startsWith('Bearer ') ? auth.slice(7) : null;
}

// ── Time ──

export function isoDaysAgo(now, days) {
  return new Date(now.getTime() - days * 86400 * 1000).toISOString();
}

// ── GitHub Releases → downloads ──

export function parseDownloads(releases) {
  const perVersion = [];
  let totalDmg = 0;
  let appcastChecks = 0;
  for (const r of releases ?? []) {
    let dmg = 0;
    let appcast = 0;
    for (const a of r.assets ?? []) {
      if (a.name?.endsWith('.dmg')) dmg += a.download_count ?? 0;
      if (a.name?.includes('appcast')) appcast += a.download_count ?? 0;
    }
    totalDmg += dmg;
    appcastChecks += appcast;
    perVersion.push({ tag: r.tag_name, dmg, appcast });
  }
  return { totalDmg, appcastChecks, perVersion };
}

// ── Analytics Engine (SQL API) → active installs + version split ──

export function buildVersionSQL(dataset, days) {
  return `SELECT blob1 AS version, SUM(_sample_interval) AS checks
          FROM ${dataset}
          WHERE timestamp > NOW() - INTERVAL '${days}' DAY
          GROUP BY version ORDER BY checks DESC`;
}

// The SQL API returns { data: [ {col: value, …} ] }.
export function parseAESql(json) {
  return (json?.data ?? []).map((row) => ({ ...row }));
}

export function aeVersionRows(json) {
  return parseAESql(json).map((r) => ({
    version: r.version ?? 'unknown',
    checks: Math.round(Number(r.checks) || 0),
  }));
}

// ── Web Analytics (RUM GraphQL) → pageviews + visits ──

export function buildRumQuery(accountTag, siteTag, start, end) {
  const query = `query Rum($accountTag: String!, $siteTag: String, $start: Time!, $end: Time!) {
    viewer { accounts(filter: { accountTag: $accountTag }) {
      rumPageloadEventsAdaptiveGroups(
        limit: 1,
        filter: { datetime_geq: $start, datetime_lt: $end, siteTag: $siteTag }
      ) { count avg { sampleInterval } sum { visits } }
    } }
  }`;
  return { query, variables: { accountTag, siteTag, start, end } };
}

export function parseRum(json) {
  const group = json?.data?.viewer?.accounts?.[0]?.rumPageloadEventsAdaptiveGroups?.[0];
  if (!group) return { pageviews: 0, visits: 0 };
  const sampleInterval = group.avg?.sampleInterval ?? 1;
  return {
    pageviews: Math.round((group.count ?? 0) * sampleInterval),
    visits: Math.round((group.sum?.visits ?? 0) * sampleInterval),
  };
}

// ── Stripe → sales count + gross ──

export function parseStripe(json) {
  const paid = (json?.data ?? []).filter((s) => s.payment_status === 'paid');
  const gross = paid.reduce((sum, s) => sum + (s.amount_total ?? 0), 0);
  return { count: paid.length, gross, currency: (paid[0]?.currency ?? 'gbp').toUpperCase() };
}

// ── Formatting ──

export function fmtInt(n) {
  return (Number(n) || 0).toLocaleString('en-GB');
}

export function fmtMoney(cents, currency) {
  const symbol = { GBP: '£', USD: '$', EUR: '€' }[currency] ?? `${currency} `;
  return `${symbol}${((Number(cents) || 0) / 100).toLocaleString('en-GB', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

// ── HTML render ──

function card(title, inner, note) {
  return `<section class="card"><h2>${esc(title)}</h2>${inner}${note ? `<p class="note">${esc(note)}</p>` : ''}</section>`;
}

function notice(text) {
  return `<p class="muted">${esc(text)}</p>`;
}

export function renderHTML(d) {
  const downloads = d.downloads.ok
    ? `<p class="big">${fmtInt(d.downloads.value.totalDmg)}</p><p class="muted">DMG downloads (all releases)</p>`
      + `<table>${d.downloads.value.perVersion.slice(0, 8).map((v) => `<tr><td>${esc(v.tag)}</td><td>${fmtInt(v.dmg)}</td></tr>`).join('')}</table>`
    : notice('GitHub unavailable.');

  const installs = d.installs.ok
    ? `<p class="big">${fmtInt(d.installs.value.active7)}</p><p class="muted">update-checks, last 7d (≈ active installs)</p>`
      + `<table>${d.installs.value.versions.map((v) => `<tr><td>${esc(v.version)}</td><td>${fmtInt(v.checks)}</td></tr>`).join('') || '<tr><td class="muted">no data yet</td></tr>'}</table>`
    : notice(d.installs.reason ?? 'Analytics Engine unavailable.');

  const traffic = d.traffic.ok
    ? `<p class="big">${fmtInt(d.traffic.value.pageviews)}</p><p class="muted">pageviews, last 7d · ${fmtInt(d.traffic.value.visits)} visits</p>`
    : notice(d.traffic.reason ?? 'Web Analytics unavailable.');

  const revenue = d.revenue.ok
    ? `<p class="big">${fmtMoney(d.revenue.value.gross, d.revenue.value.currency)}</p><p class="muted">${fmtInt(d.revenue.value.count)} sales (last 100 checkouts)</p>`
    : notice(d.revenue.reason ?? 'Stripe unavailable.');

  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>SharePad stats</title>
<style>
:root { color-scheme: light dark; }
body { font: 15px/1.5 -apple-system, system-ui, sans-serif; margin: 0; padding: 24px;
  background: Canvas; color: CanvasText; }
header { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 16px; }
h1 { font-size: 1.25rem; margin: 0; }
.grid { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); }
.card { border: 1px solid color-mix(in srgb, CanvasText 15%, transparent); border-radius: 12px; padding: 16px; }
.card h2 { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.04em; opacity: 0.7; margin: 0 0 8px; }
.big { font-size: 2rem; font-weight: 650; margin: 0; }
.muted { opacity: 0.6; margin: 2px 0; font-size: 0.85rem; }
.note { opacity: 0.5; font-size: 0.78rem; margin-top: 10px; }
table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 0.85rem; }
td { padding: 3px 0; border-top: 1px solid color-mix(in srgb, CanvasText 8%, transparent); }
td:last-child { text-align: right; font-variant-numeric: tabular-nums; }
</style></head><body>
<header><h1>SharePad stats</h1><span class="muted">${esc(d.generatedAt)}</span></header>
<div class="grid">
${card('Downloads', downloads)}
${card('Active installs', installs)}
${card('Site traffic', traffic)}
${card('Revenue', revenue)}
</div>
</body></html>`;
}
