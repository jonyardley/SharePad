import assert from "node:assert/strict";
import { test } from "node:test";
import { base64url, licenseKey, normalizeEmail, purchaseEmailHtml, purchaseEmailText } from "../src/worker.js";

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
