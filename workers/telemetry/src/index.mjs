// Opt-in crash/diagnostic sink for SharePad. See specs/telemetry.md.
// Receives anonymous JSON from the app (only when the user has opted in): crash
// and hang diagnostics from MetricKit, plus named non-fatal events. Writes a
// time-series point to Analytics Engine and stores raw crash/hang payloads in R2.
// A backend problem must NEVER surface in the app, so every write fails soft and
// the handler always answers quickly.

const MAX_BYTES = 256 * 1024;
const KINDS = new Set(['crash', 'hang', 'event']);

// Pure: validate + normalise a request body into a report, or null if malformed.
// Never trusts client strings for length; callers cap the raw body separately.
export function parseReport(text) {
  let raw;
  try {
    raw = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof raw !== 'object' || raw === null) return null;
  const kind = raw.kind;
  if (!KINDS.has(kind)) return null;
  const name = typeof raw.name === 'string' && raw.name ? raw.name.slice(0, 256) : 'unknown';
  const appVersion = typeof raw.appVersion === 'string' ? raw.appVersion.slice(0, 32) : 'unknown';
  const osVersion = typeof raw.osVersion === 'string' ? raw.osVersion.slice(0, 32) : 'unknown';
  // Payloads are only meaningful for crash/hang; events carry none.
  const hasPayload = (kind === 'crash' || kind === 'hang') && raw.payload != null;
  return { kind, name, appVersion, osVersion, payload: hasPayload ? raw.payload : null };
}

// Pure: a date-partitioned, collision-free R2 key.
export function r2Key(date, id) {
  const yyyy = date.getUTCFullYear();
  const mm = String(date.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(date.getUTCDate()).padStart(2, '0');
  return `${yyyy}/${mm}/${dd}/${id}.json`;
}

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return new Response('Method not allowed\n', { status: 405, headers: { allow: 'POST' } });
    }
    if (new URL(request.url).pathname !== '/report') {
      return new Response('Not found\n', { status: 404 });
    }
    // Our client always sends a SharePad User-Agent; anything else is not us.
    if (!(request.headers.get('user-agent') ?? '').includes('SharePad')) {
      return new Response('Bad request\n', { status: 400 });
    }

    const text = await request.text();
    if (text.length > MAX_BYTES) {
      return new Response('Payload too large\n', { status: 400 });
    }
    const report = parseReport(text);
    if (!report) {
      return new Response('Bad request\n', { status: 400 });
    }

    const country = request.cf?.country ?? 'XX';

    try {
      env.AE?.writeDataPoint({
        blobs: [report.kind, report.name, report.appVersion, report.osVersion, country],
        indexes: [report.kind],
        doubles: [1],
      });
    } catch {
      // Telemetry is best-effort; a logging error never affects the response.
    }

    if (report.payload != null) {
      try {
        await env.DIAGNOSTICS?.put(
          r2Key(new Date(), crypto.randomUUID()),
          JSON.stringify({
            kind: report.kind,
            name: report.name,
            appVersion: report.appVersion,
            osVersion: report.osVersion,
            country,
            payload: report.payload,
          }),
          { httpMetadata: { contentType: 'application/json' } },
        );
      } catch {
        // R2 outage must not fail the request; the AE count still landed.
      }
    }

    return new Response(null, { status: 204 });
  },
};
