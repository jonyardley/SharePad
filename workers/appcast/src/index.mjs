// Logging proxy for the Sparkle appcast. See specs/appcast-analytics.md.
// Serves the gh-pages appcast (the single source of truth) and records one
// anonymous data point per update-check. A logging outage must NEVER break
// auto-update, so both the AE write and the upstream fetch fail soft.

const UPSTREAM = 'https://sharepad.co/appcast.xml';

// Sparkle's default User-Agent is "<CFBundleName>/<shortVersion> Sparkle/<ver>".
// We only want the app version; anything we can't parse is bucketed as "unknown"
// (browsers, crawlers, format surprises) so it's filterable, not lost.
export function parseAppVersion(userAgent) {
  if (!userAgent) return 'unknown';
  const match = /SharePad\/(\d+\.\d+(?:\.\d+)?)/.exec(userAgent);
  return match ? match[1] : 'unknown';
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== '/appcast.xml') {
      return new Response('Not found\n', { status: 404, headers: { 'cache-control': 'no-store' } });
    }

    const userAgent = request.headers.get('user-agent') ?? '';
    const appVersion = parseAppVersion(userAgent);
    const country = request.cf?.country ?? 'XX';

    // Fire-and-forget. The raw UA (truncated) is kept as a fallback blob so a
    // User-Agent format change is recoverable rather than silently mis-bucketed.
    try {
      env.AE?.writeDataPoint({
        blobs: [appVersion, country, userAgent.slice(0, 256)],
        indexes: [appVersion],
        doubles: [1],
      });
    } catch {
      // Logging is best-effort; never let it affect the served appcast.
    }

    let upstream;
    try {
      upstream = await fetch(UPSTREAM, { cf: { cacheTtl: 300, cacheEverything: true } });
    } catch {
      return new Response('Upstream unavailable\n', { status: 502, headers: { 'cache-control': 'no-store' } });
    }

    const headers = new Headers({ 'cache-control': 'public, max-age=300' });
    if (upstream.ok) headers.set('content-type', 'application/xml; charset=utf-8');
    return new Response(upstream.body, { status: upstream.status, headers });
  },
};
