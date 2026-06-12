export function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

export function base64url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export async function importPrivateKey(pkcs8Base64) {
  const der = Uint8Array.from(atob(pkcs8Base64), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey('pkcs8', der, { name: 'Ed25519' }, false, ['sign']);
}

export async function licenseKey(privateKey, email) {
  const message = new TextEncoder().encode(normalizeEmail(email));
  const signature = await crypto.subtle.sign('Ed25519', privateKey, message);
  return base64url(new Uint8Array(signature));
}

export function escapeHtml(text) {
  const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  return text.replace(/[&<>"']/g, (c) => map[c]);
}
