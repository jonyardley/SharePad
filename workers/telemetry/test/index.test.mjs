import assert from 'node:assert/strict';
import { test } from 'node:test';
import worker, { parseReport, r2Key } from '../src/index.mjs';

const UA = { 'user-agent': 'SharePad/1.2.0' };

// Records writeDataPoint calls; optionally throws to prove logging is fail-soft.
function fakeAE({ throwOnWrite = false } = {}) {
  const points = [];
  return {
    points,
    writeDataPoint(p) {
      if (throwOnWrite) throw new Error('AE down');
      points.push(p);
    },
  };
}

// Records R2 puts; optionally throws/rejects to prove storage is fail-soft.
function fakeR2({ throwOnPut = false } = {}) {
  const puts = [];
  return {
    puts,
    async put(key, value) {
      if (throwOnPut) throw new Error('R2 down');
      puts.push({ key, value });
    },
  };
}

function post(body, { headers = UA } = {}) {
  return new Request('https://telemetry.test/report', {
    method: 'POST',
    headers,
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

test('parseReport accepts a named event and drops any payload it carries', () => {
  const r = parseReport(JSON.stringify({ kind: 'event', name: 'shareLost', appVersion: '1.2.0', osVersion: '14.5', payload: { x: 1 } }));
  assert.deepEqual(r, { kind: 'event', name: 'shareLost', appVersion: '1.2.0', osVersion: '14.5', payload: null });
});

test('parseReport keeps a payload only for crash/hang', () => {
  const crash = parseReport(JSON.stringify({ kind: 'crash', name: 'SIGSEGV', appVersion: '1.2.0', osVersion: '14.5', payload: { stack: 'x' } }));
  assert.deepEqual(crash.payload, { stack: 'x' });
});

test('parseReport rejects malformed bodies and unknown kinds', () => {
  assert.equal(parseReport('not json'), null);
  assert.equal(parseReport(JSON.stringify(['array'])), null);
  assert.equal(parseReport(JSON.stringify({ kind: 'wat' })), null);
});

test('parseReport defaults missing fields to unknown', () => {
  const r = parseReport(JSON.stringify({ kind: 'event' }));
  assert.deepEqual(r, { kind: 'event', name: 'unknown', appVersion: 'unknown', osVersion: 'unknown', payload: null });
});

test('r2Key partitions by UTC date', () => {
  assert.equal(r2Key(new Date('2026-09-07T23:15:00Z'), 'abc'), '2026/09/07/abc.json');
});

test('a named event writes one AE point and no R2 object, returns 204', async () => {
  const ae = fakeAE();
  const r2 = fakeR2();
  const res = await worker.fetch(post({ kind: 'event', name: 'shareLost', appVersion: '1.2.0', osVersion: '14.5' }), { AE: ae, DIAGNOSTICS: r2 });
  assert.equal(res.status, 204);
  assert.equal(ae.points.length, 1);
  assert.deepEqual(ae.points[0].indexes, ['event']);
  assert.deepEqual(ae.points[0].blobs, ['event', 'shareLost', '1.2.0', '14.5', 'XX']);
  assert.equal(r2.puts.length, 0);
});

test('a crash writes AE and one R2 object', async () => {
  const ae = fakeAE();
  const r2 = fakeR2();
  const res = await worker.fetch(post({ kind: 'crash', name: 'SIGSEGV', appVersion: '1.2.0', osVersion: '14.5', payload: { stack: 'top' } }), { AE: ae, DIAGNOSTICS: r2 });
  assert.equal(res.status, 204);
  assert.equal(ae.points.length, 1);
  assert.equal(r2.puts.length, 1);
  assert.match(r2.puts[0].key, /^\d{4}\/\d{2}\/\d{2}\/.+\.json$/);
  assert.match(r2.puts[0].value, /"payload"/);
});

test('an oversized body is rejected with 400', async () => {
  const big = 'x'.repeat(256 * 1024 + 1);
  const res = await worker.fetch(post(JSON.stringify({ kind: 'event', name: big })), { AE: fakeAE(), DIAGNOSTICS: fakeR2() });
  assert.equal(res.status, 400);
});

test('a non-SharePad User-Agent is rejected', async () => {
  const res = await worker.fetch(post({ kind: 'event', name: 'shareLost' }, { headers: { 'user-agent': 'curl/8' } }), { AE: fakeAE() });
  assert.equal(res.status, 400);
});

test('a GET is 405', async () => {
  const res = await worker.fetch(new Request('https://telemetry.test/report', { headers: UA }), { AE: fakeAE() });
  assert.equal(res.status, 405);
});

test('an unknown path is 404', async () => {
  const res = await worker.fetch(new Request('https://telemetry.test/other', { method: 'POST', headers: UA, body: '{}' }), { AE: fakeAE() });
  assert.equal(res.status, 404);
});

test('a throwing AE binding still returns 204', async () => {
  const res = await worker.fetch(post({ kind: 'event', name: 'shareLost' }), { AE: fakeAE({ throwOnWrite: true }), DIAGNOSTICS: fakeR2() });
  assert.equal(res.status, 204);
});

test('a throwing R2 binding still returns 204', async () => {
  const res = await worker.fetch(post({ kind: 'crash', name: 'SIGSEGV', payload: { stack: 'x' } }), { AE: fakeAE(), DIAGNOSTICS: fakeR2({ throwOnPut: true }) });
  assert.equal(res.status, 204);
});

test('missing bindings do not throw', async () => {
  const res = await worker.fetch(post({ kind: 'crash', name: 'SIGSEGV', payload: { stack: 'x' } }), {});
  assert.equal(res.status, 204);
});
