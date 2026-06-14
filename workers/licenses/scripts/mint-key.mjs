// Usage: ED25519_PRIVATE_KEY=<pkcs8 base64> node scripts/mint-key.mjs buyer@example.com
import { importPrivateKey, licenseKey } from '../src/license.mjs';

const email = process.argv[2];
const secret = process.env.ED25519_PRIVATE_KEY;
if (!email || !secret) {
  console.error('Usage: ED25519_PRIVATE_KEY=<pkcs8 base64> node scripts/mint-key.mjs <email>');
  process.exit(1);
}
console.log(await licenseKey(await importPrivateKey(secret), email));
