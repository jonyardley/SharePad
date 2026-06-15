// Stats dashboard Worker. See specs/stats-dashboard.md.

import {
  aeVersionRows, buildRumQuery, buildVersionSQL, isoDaysAgo,
  parseDownloads, parseRum, parseStripe, presentedToken, renderHTML, tokensMatch,
} from './lib.mjs';

export default {
  async fetch(request, env) {
    if (!env.DASHBOARD_TOKEN) {
      return text('Dashboard not configured: set the DASHBOARD_TOKEN secret.', 503);
    }
    const url = new URL(request.url);
    if (!tokensMatch(presentedToken(request), env.DASHBOARD_TOKEN)) {
      return text('Unauthorized', 401, { 'www-authenticate': 'Bearer' });
    }
    // Token arrived in the URL → move it into an httpOnly cookie and strip it from
    // the address bar so it doesn't linger in history / referrers.
    if (url.searchParams.get('token')) {
      return new Response(null, {
        status: 302,
        headers: {
          location: url.pathname,
          'set-cookie': `dash=${encodeURIComponent(env.DASHBOARD_TOKEN)}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=2592000`,
        },
      });
    }

    const data = await gather(env);
    return new Response(renderHTML(data), {
      headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' },
    });
  },
};

function text(body, status, extra = {}) {
  return new Response(`${body}\n`, { status, headers: { 'content-type': 'text/plain; charset=utf-8', ...extra } });
}

async function gather(env) {
  const [downloads, installs, traffic, revenue] = await Promise.all([
    safe('downloads', () => fetchDownloads(env)),
    env.CF_API_TOKEN ? safe('installs', () => fetchInstalls(env)) : unconfigured('CF_API_TOKEN not set'),
    env.CF_API_TOKEN ? safe('traffic', () => fetchTraffic(env)) : unconfigured('CF_API_TOKEN not set'),
    env.STRIPE_API_KEY ? safe('revenue', () => fetchRevenue(env)) : unconfigured('STRIPE_API_KEY not set'),
  ]);
  const generatedAt = `${new Date().toISOString().replace('T', ' ').slice(0, 16)} UTC`;
  return { generatedAt, downloads, installs, traffic, revenue };
}

const unconfigured = (reason) => Promise.resolve({ ok: false, reason });

async function safe(key, fn) {
  try {
    return await cached(key, 300, async () => ({ ok: true, value: await fn() }));
  } catch (error) {
    return { ok: false, reason: error.message };
  }
}

async function cached(key, ttl, fn) {
  const cache = caches.default;
  const cacheKey = new Request(`https://stats-cache.internal/${key}`);
  const hit = await cache.match(cacheKey);
  if (hit) return hit.json();
  const value = await fn();
  await cache.put(cacheKey, new Response(JSON.stringify(value), { headers: { 'cache-control': `max-age=${ttl}` } }));
  return value;
}

async function fetchDownloads(env) {
  const res = await fetch(`https://api.github.com/repos/${env.GITHUB_REPO}/releases?per_page=100`, {
    headers: { 'user-agent': 'sharepad-stats', accept: 'application/vnd.github+json' },
  });
  if (!res.ok) throw new Error(`GitHub ${res.status}`);
  return parseDownloads(await res.json());
}

async function fetchInstalls(env) {
  const json = await aeSql(env, buildVersionSQL(env.AE_DATASET, 7));
  const versions = aeVersionRows(json);
  return { active7: versions.reduce((sum, v) => sum + v.checks, 0), versions };
}

async function aeSql(env, sql) {
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${env.CF_ACCOUNT_ID}/analytics_engine/sql`, {
    method: 'POST',
    headers: { authorization: `Bearer ${env.CF_API_TOKEN}` },
    body: sql,
  });
  if (!res.ok) throw new Error(`Analytics Engine ${res.status}`);
  return res.json();
}

async function fetchTraffic(env) {
  const now = new Date();
  const { query, variables } = buildRumQuery(
    env.CF_ACCOUNT_ID, env.WEB_ANALYTICS_SITE_TAG, isoDaysAgo(now, 7), now.toISOString(),
  );
  const res = await fetch('https://api.cloudflare.com/client/v4/graphql', {
    method: 'POST',
    headers: { authorization: `Bearer ${env.CF_API_TOKEN}`, 'content-type': 'application/json' },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) throw new Error(`Web Analytics ${res.status}`);
  const json = await res.json();
  if (json.errors?.length) throw new Error(`Web Analytics: ${json.errors[0].message}`);
  return parseRum(json);
}

async function fetchRevenue(env) {
  const res = await fetch('https://api.stripe.com/v1/checkout/sessions?status=complete&limit=100', {
    headers: { authorization: `Bearer ${env.STRIPE_API_KEY}` },
  });
  if (!res.ok) throw new Error(`Stripe ${res.status}`);
  return parseStripe(await res.json());
}
