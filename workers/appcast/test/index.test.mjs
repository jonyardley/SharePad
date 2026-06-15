import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import worker, { parseAppVersion } from '../src/index.mjs';

const realFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = realFetch; });

const APPCAST = '<?xml version="1.0"?><rss><channel><item/></channel></rss>';

function stubUpstream(body = APPCAST, status = 200) {
  globalThis.fetch = async () => new Response(body, { status });
}

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

test('parseAppVersion extracts the version from a Sparkle User-Agent', () => {
  assert.equal(parseAppVersion('SharePad/1.1.0 Sparkle/2.9.2'), '1.1.0');
  assert.equal(parseAppVersion('SharePad/2.0 Sparkle/2'), '2.0');
});

test('parseAppVersion buckets unknown / missing User-Agents', () => {
  assert.equal(parseAppVersion(''), 'unknown');
  assert.equal(parseAppVersion(undefined), 'unknown');
  assert.equal(parseAppVersion('Mozilla/5.0 (Macintosh)'), 'unknown');
});

test('/appcast.xml proxies the upstream body as XML', async () => {
  stubUpstream();
  const ae = fakeAE();
  const response = await worker.fetch(
    new Request('https://appcast.test/appcast.xml', { headers: { 'user-agent': 'SharePad/1.1.0 Sparkle/2.9.2' } }),
    { AE: ae },
  );
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /application\/xml/);
  assert.equal(await response.text(), APPCAST);
});

test('/appcast.xml logs one data point with the parsed version', async () => {
  stubUpstream();
  const ae = fakeAE();
  await worker.fetch(
    new Request('https://appcast.test/appcast.xml', { headers: { 'user-agent': 'SharePad/1.1.0 Sparkle/2.9.2' } }),
    { AE: ae },
  );
  assert.equal(ae.points.length, 1);
  assert.deepEqual(ae.points[0].indexes, ['1.1.0']);
  assert.equal(ae.points[0].blobs[0], '1.1.0');
});

test('a logging failure never breaks the served appcast', async () => {
  stubUpstream();
  const response = await worker.fetch(
    new Request('https://appcast.test/appcast.xml', { headers: { 'user-agent': 'SharePad/1.1.0 Sparkle/2.9.2' } }),
    { AE: fakeAE({ throwOnWrite: true }) },
  );
  assert.equal(response.status, 200);
  assert.equal(await response.text(), APPCAST);
});

test('a missing AE binding does not throw', async () => {
  stubUpstream();
  const response = await worker.fetch(new Request('https://appcast.test/appcast.xml'), {});
  assert.equal(response.status, 200);
});

test('an upstream outage returns 502, not a thrown error', async () => {
  globalThis.fetch = async () => { throw new Error('network down'); };
  const response = await worker.fetch(new Request('https://appcast.test/appcast.xml'), { AE: fakeAE() });
  assert.equal(response.status, 502);
});

test('unknown paths are 404', async () => {
  const response = await worker.fetch(new Request('https://appcast.test/'), { AE: fakeAE() });
  assert.equal(response.status, 404);
});
