// Cloudflare Access JWT verification (signature + claims). See specs/stats-dashboard.md.
// Lets a request that came through Access authorize without the DASHBOARD_TOKEN.

import { accessClaimsValid, accessTokenFromRequest, decodeJwtSegment } from './lib.mjs';

function b64urlToBytes(s) {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64.padEnd(b64.length + ((4 - (b64.length % 4)) % 4), '='));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// Access publishes its signing keys here; cache an hour (keys rotate slowly).
async function accessKeys(teamDomain) {
  const res = await fetch(`https://${teamDomain}/cdn-cgi/access/certs`, {
    cf: { cacheTtl: 3600, cacheEverything: true },
  });
  if (!res.ok) throw new Error(`access certs ${res.status}`);
  return (await res.json()).keys ?? [];
}

// True only for a request carrying a valid, correctly-audienced, unexpired,
// signature-verified Access JWT for this app. False (never throws) otherwise, so
// the caller falls back to the token gate.
export async function accessVerified(request, env) {
  const { ACCESS_TEAM_DOMAIN: teamDomain, ACCESS_AUD: aud } = env;
  if (!teamDomain || !aud) return false;
  const token = accessTokenFromRequest(request);
  if (!token) return false;
  const parts = token.split('.');
  if (parts.length !== 3) return false;

  let header;
  let payload;
  try {
    header = decodeJwtSegment(parts[0]);
    payload = decodeJwtSegment(parts[1]);
  } catch {
    return false;
  }
  if (!accessClaimsValid(payload, teamDomain, aud, Math.floor(Date.now() / 1000))) return false;

  try {
    const jwk = (await accessKeys(teamDomain)).find((k) => k.kid === header.kid);
    if (!jwk) return false;
    const key = await crypto.subtle.importKey(
      'jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'],
    );
    return await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5', key, b64urlToBytes(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
  } catch {
    return false;
  }
}
