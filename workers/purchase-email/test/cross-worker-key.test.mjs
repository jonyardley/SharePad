import assert from "node:assert/strict";
import { test } from "node:test";
import { licenseKey as emailLicenseKey, normalizeEmail as emailNormalize } from "../src/worker.js";
import { licenseKey as licensesLicenseKey, normalizeEmail as licensesNormalize } from "../../licenses/src/license.mjs";

async function key() {
  const { privateKey } = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  return privateKey;
}

test("both workers derive the identical licence key for the same email", async () => {
  const pk = await key();
  for (const email of ["Buyer@Example.com", "  spaced@x.io \n", "u.ser+tag@gmail.com"]) {
    assert.equal(emailNormalize(email), licensesNormalize(email));
    assert.equal(await emailLicenseKey(pk, email), await licensesLicenseKey(pk, email));
  }
});
