import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import worker, {
  base64url,
  licenseKey,
  normalizeEmail,
  purchaseEmailHtml,
  purchaseEmailText,
  verifyStripeSignature,
} from "../src/worker.js";

test("normalizeEmail trims and lowercases", () => {
  assert.equal(normalizeEmail("  Buyer@Example.COM \n"), "buyer@example.com");
});

test("base64url has no padding or url-unsafe chars", () => {
  const encoded = base64url(new Uint8Array([251, 255, 190, 62, 63, 0]));
  assert.ok(!/[+/=]/.test(encoded));
});

test("licenseKey verifies against WebCrypto and matches the normalized email", async () => {
  const { publicKey, privateKey } = await crypto.subtle.generateKey(
    { name: "Ed25519" }, true, ["sign", "verify"],
  );
  const key = await licenseKey(privateKey, "  Buyer@Example.com ");
  const padded = key.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(key.length / 4) * 4, "=");
  const signature = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
  const valid = await crypto.subtle.verify(
    "Ed25519", publicKey, signature, new TextEncoder().encode("buyer@example.com"),
  );
  assert.equal(valid, true);
});

test("purchaseEmailHtml includes the download link, normalized email, key, and recover link; no emoji", () => {
  const html = purchaseEmailHtml(
    "https://sharepad.co/download",
    "  Buyer@Example.com ",
    "ABC-key_123",
    "https://w.test/recover",
  );
  assert.ok(html.includes("https://sharepad.co/download"));
  assert.ok(html.includes("buyer@example.com"));
  assert.ok(html.includes("ABC-key_123"));
  assert.ok(html.includes("https://w.test/recover"));
  assert.ok(!/\p{Extended_Pictographic}/u.test(html));
});

test("purchaseEmailHtml escapes a hostile email", () => {
  const html = purchaseEmailHtml("u", "<img src=x>@y.z", "k", "r");
  assert.ok(!html.includes("<img"));
});

test("purchaseEmailHtml uses a bulletproof button and avoids rgba/pre", () => {
  const html = purchaseEmailHtml("https://sharepad.co/download", "b@y.z", "K", "r");
  assert.ok(html.includes('bgcolor="#3E4CB3"'));
  assert.ok(!html.includes("rgba("));
  assert.ok(!html.includes("<pre"));
});

test("purchaseEmailText includes the download link, normalized email, key, and recover link; no emoji", () => {
  const text = purchaseEmailText(
    "https://sharepad.co/download",
    "  Buyer@Example.com ",
    "ABC-key_123",
    "https://w.test/recover",
  );
  assert.ok(text.includes("https://sharepad.co/download"));
  assert.ok(text.includes("buyer@example.com"));
  assert.ok(text.includes("ABC-key_123"));
  assert.ok(text.includes("https://w.test/recover"));
  assert.ok(!/\p{Extended_Pictographic}/u.test(text));
});

// ── Webhook fetch-level tests ──

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

async function hmacHex(secret, message) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const WEBHOOK_SECRET = "whsec_test";

async function signedHeader(body, timestamp) {
  const t = timestamp ?? Math.floor(Date.now() / 1000);
  return `t=${t},v1=${await hmacHex(WEBHOOK_SECRET, `${t}.${body}`)}`;
}

async function env() {
  const { privateKey } = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", privateKey)).toString("base64");
  return { ED25519_PRIVATE_KEY: pkcs8, STRIPE_WEBHOOK_SECRET: WEBHOOK_SECRET, RESEND_API_KEY: "re_test" };
}

function paidEvent(email = "Buyer@Example.com") {
  return JSON.stringify({
    type: "checkout.session.completed",
    data: { object: { payment_status: "paid", customer_details: { email } } },
  });
}

function post(body, header) {
  return new Request("https://w.test/", { method: "POST", body, headers: header ? { "stripe-signature": header } : {} });
}

function stubResend(ok = true) {
  globalThis.fetch = async () => new Response(ok ? "{}" : "fail", { status: ok ? 200 : 500 });
}

test("valid paid webhook returns 200 and calls Resend", async () => {
  let called = 0;
  globalThis.fetch = async (url) => { if (String(url).includes("resend.com")) called++; return new Response("{}", { status: 200 }); };
  const body = paidEvent();
  const res = await worker.fetch(post(body, await signedHeader(body)), await env());
  assert.equal(res.status, 200);
  assert.equal(called, 1);
});

test("tampered signature is rejected with 400", async () => {
  const body = paidEvent();
  const header = await signedHeader("different-body");
  const res = await worker.fetch(post(body, header), await env());
  assert.equal(res.status, 400);
});

test("missing signature header is 400", async () => {
  const body = paidEvent();
  const res = await worker.fetch(post(body, undefined), await env());
  assert.equal(res.status, 400);
});

test("stale timestamp outside the replay window is 400", async () => {
  const body = paidEvent();
  const old = Math.floor(Date.now() / 1000) - 600;
  const res = await worker.fetch(post(body, await signedHeader(body, old)), await env());
  assert.equal(res.status, 400);
});

test("completed-but-unpaid session does not send and returns 200", async () => {
  let called = 0;
  globalThis.fetch = async (url) => { if (String(url).includes("resend.com")) called++; return new Response("{}", { status: 200 }); };
  const body = JSON.stringify({ type: "checkout.session.completed", data: { object: { payment_status: "unpaid", customer_details: { email: "a@b.c" } } } });
  const res = await worker.fetch(post(body, await signedHeader(body)), await env());
  assert.equal(res.status, 200);
  assert.equal(called, 0);
});

test("paid checkout with no customer email returns 200 and does not send", async () => {
  let called = 0;
  globalThis.fetch = async (url) => { if (String(url).includes("resend.com")) called++; return new Response("{}", { status: 200 }); };
  const body = JSON.stringify({ type: "checkout.session.completed", data: { object: { payment_status: "paid", customer_details: {} } } });
  const res = await worker.fetch(post(body, await signedHeader(body)), await env());
  assert.equal(res.status, 200);
  assert.equal(called, 0);
});

test("non-checkout event is ignored with 200", async () => {
  const body = JSON.stringify({ type: "payment_intent.succeeded", data: { object: {} } });
  const res = await worker.fetch(post(body, await signedHeader(body)), await env());
  assert.equal(res.status, 200);
});

test("resend failure returns 500 so Stripe retries", async () => {
  stubResend(false);
  const body = paidEvent();
  const res = await worker.fetch(post(body, await signedHeader(body)), await env());
  assert.equal(res.status, 500);
});

test("non-POST is 405", async () => {
  const res = await worker.fetch(new Request("https://w.test/", { method: "GET" }), await env());
  assert.equal(res.status, 405);
});

test("verifyStripeSignature accepts a valid signature and rejects tampering", async () => {
  const body = "payload";
  assert.equal(await verifyStripeSignature(body, await signedHeader(body), WEBHOOK_SECRET), true);
  assert.equal(await verifyStripeSignature(body, await signedHeader(body), "wrong"), false);
  assert.equal(await verifyStripeSignature(body, "garbage", WEBHOOK_SECRET), false);
  assert.equal(await verifyStripeSignature(body, await signedHeader(body), ""), false);
});
