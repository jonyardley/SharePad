import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  accessClaimsValid, accessTokenFromRequest, aeVersionRows, buildRumQuery, buildVersionSQL,
  decodeJwtSegment, fmtInt, fmtMoney, isoDaysAgo, parseDownloads, parseRum, parseStripe,
  presentedToken, renderHTML, tokensMatch,
} from '../src/lib.mjs';

// ── auth ──

test('tokensMatch is true only for an exact match', () => {
  assert.equal(tokensMatch('secret123', 'secret123'), true);
  assert.equal(tokensMatch('secret123', 'secret124'), false);
  assert.equal(tokensMatch('short', 'longer-secret'), false);
  assert.equal(tokensMatch('', 'x'), false);
  assert.equal(tokensMatch(null, 'x'), false);
});

test('presentedToken reads query, then cookie, then bearer', () => {
  assert.equal(presentedToken(new Request('https://s.test/?token=abc')), 'abc');
  assert.equal(
    presentedToken(new Request('https://s.test/', { headers: { cookie: 'foo=1; dash=xyz' } })),
    'xyz',
  );
  assert.equal(
    presentedToken(new Request('https://s.test/', { headers: { authorization: 'Bearer tok' } })),
    'tok',
  );
  assert.equal(presentedToken(new Request('https://s.test/')), null);
});

// ── Cloudflare Access ──

test('accessTokenFromRequest reads the header, then the cookie', () => {
  assert.equal(
    accessTokenFromRequest(new Request('https://s.test/', { headers: { 'cf-access-jwt-assertion': 'jwt1' } })),
    'jwt1',
  );
  assert.equal(
    accessTokenFromRequest(new Request('https://s.test/', { headers: { cookie: 'x=1; CF_Authorization=jwt2' } })),
    'jwt2',
  );
  assert.equal(accessTokenFromRequest(new Request('https://s.test/')), null);
});

test('decodeJwtSegment decodes base64url JSON', () => {
  const seg = Buffer.from(JSON.stringify({ kid: 'k1' })).toString('base64url');
  assert.deepEqual(decodeJwtSegment(seg), { kid: 'k1' });
});

test('accessClaimsValid enforces aud, expiry, and issuer', () => {
  const team = 'team.cloudflareaccess.com';
  const aud = 'app-aud';
  const now = 1000;
  assert.equal(accessClaimsValid({ aud, exp: 2000, iss: `https://${team}` }, team, aud, now), true);
  assert.equal(accessClaimsValid({ aud: ['other', aud], exp: 2000 }, team, aud, now), true); // aud array
  assert.equal(accessClaimsValid({ aud, exp: 500 }, team, aud, now), false);                  // expired
  assert.equal(accessClaimsValid({ aud: 'wrong', exp: 2000 }, team, aud, now), false);        // wrong aud
  assert.equal(accessClaimsValid({ aud, exp: 2000, iss: 'https://evil.com' }, team, aud, now), false); // wrong issuer
  assert.equal(accessClaimsValid(null, team, aud, now), false);
});

// ── downloads ──

test('parseDownloads sums .dmg and appcast counts across releases', () => {
  const releases = [
    { tag_name: 'v1.2.0', assets: [{ name: 'SharePad.dmg', download_count: 10 }, { name: 'appcast.xml', download_count: 4 }] },
    { tag_name: 'v1.1.0', assets: [{ name: 'SharePad.dmg', download_count: 5 }] },
  ];
  const d = parseDownloads(releases);
  assert.equal(d.totalDmg, 15);
  assert.equal(d.appcastChecks, 4);
  assert.equal(d.perVersion.length, 2);
  assert.deepEqual(d.perVersion[0], { tag: 'v1.2.0', dmg: 10, appcast: 4 });
});

test('parseDownloads tolerates empty / missing assets', () => {
  assert.deepEqual(parseDownloads([]), { totalDmg: 0, appcastChecks: 0, perVersion: [] });
  assert.deepEqual(parseDownloads(undefined), { totalDmg: 0, appcastChecks: 0, perVersion: [] });
});

// ── analytics engine ──

test('buildVersionSQL targets the dataset and window', () => {
  const sql = buildVersionSQL('sharepad_appcast', 7);
  assert.match(sql, /FROM sharepad_appcast/);
  assert.match(sql, /INTERVAL '7' DAY/);
  assert.match(sql, /SUM\(_sample_interval\)/);
});

test('aeVersionRows parses the SQL API shape', () => {
  const json = { data: [{ version: '1.2.0', checks: '42' }, { version: 'unknown', checks: 3 }] };
  assert.deepEqual(aeVersionRows(json), [{ version: '1.2.0', checks: 42 }, { version: 'unknown', checks: 3 }]);
  assert.deepEqual(aeVersionRows({}), []);
});

// ── web analytics (RUM) ──

test('buildRumQuery wires account, site, and window', () => {
  const { query, variables } = buildRumQuery('acct', 'site', '2026-06-08T00:00:00Z', '2026-06-15T00:00:00Z');
  assert.match(query, /rumPageloadEventsAdaptiveGroups/);
  assert.deepEqual(variables, { accountTag: 'acct', siteTag: 'site', start: '2026-06-08T00:00:00Z', end: '2026-06-15T00:00:00Z' });
});

test('parseRum applies the sample interval and defaults to zero', () => {
  const json = { data: { viewer: { accounts: [{ rumPageloadEventsAdaptiveGroups: [{ count: 100, avg: { sampleInterval: 2 }, sum: { visits: 30 } }] }] } } };
  assert.deepEqual(parseRum(json), { pageviews: 200, visits: 60 });
  assert.deepEqual(parseRum({}), { pageviews: 0, visits: 0 });
});

// ── stripe ──

test('parseStripe sums paid sessions only', () => {
  const json = { data: [
    { payment_status: 'paid', amount_total: 699, currency: 'gbp' },
    { payment_status: 'paid', amount_total: 699, currency: 'gbp' },
    { payment_status: 'unpaid', amount_total: 699, currency: 'gbp' },
  ] };
  assert.deepEqual(parseStripe(json), { count: 2, gross: 1398, currency: 'GBP' });
  assert.deepEqual(parseStripe({}), { count: 0, gross: 0, currency: 'GBP' });
});

// ── formatting ──

test('formatters', () => {
  assert.equal(fmtInt(1234), '1,234');
  assert.equal(fmtMoney(1398, 'GBP'), '£13.98');
  assert.equal(fmtMoney(0, 'USD'), '$0.00');
});

test('isoDaysAgo subtracts whole days', () => {
  const now = new Date('2026-06-15T00:00:00.000Z');
  assert.equal(isoDaysAgo(now, 7), '2026-06-08T00:00:00.000Z');
});

// ── render: graceful degradation ──

test('renderHTML shows data when ok and a notice when not', () => {
  const html = renderHTML({
    generatedAt: '2026-06-15 18:00 UTC',
    downloads: { ok: true, value: { totalDmg: 15, perVersion: [{ tag: 'v1.2.0', dmg: 10 }] } },
    installs: { ok: false, reason: 'CF_API_TOKEN not set' },
    traffic: { ok: false, reason: 'CF_API_TOKEN not set' },
    revenue: { ok: true, value: { gross: 1398, count: 2, currency: 'GBP' } },
  });
  assert.match(html, /SharePad stats/);
  assert.match(html, /15/);            // downloads value
  assert.match(html, /£13\.98/);       // revenue
  assert.match(html, /CF_API_TOKEN not set/); // degraded card notice
  assert.match(html, /noindex/);       // not indexable
});
