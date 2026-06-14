// Stripe checkout.session.completed -> branded email with the download link AND
// the buyer's offline licence key (via Resend). This is the single, exactly-once
// post-purchase email: the webhook fires once per paid checkout, so a buyer who
// closes the thank-you tab still gets both their download and their key.
// See specs/purchase-flow.md.

const SIG_TOLERANCE_SECONDS = 300;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    const signature = request.headers.get("stripe-signature");
    const rawBody = await request.text();

    if (!signature || !(await verifyStripeSignature(rawBody, signature, env.STRIPE_WEBHOOK_SECRET))) {
      return new Response("Invalid signature", { status: 400 });
    }

    let event;
    try {
      event = JSON.parse(rawBody);
    } catch {
      return new Response("Bad JSON", { status: 400 });
    }

    // Only act on completed checkouts; acknowledge everything else so Stripe
    // doesn't retry events we intentionally ignore.
    if (event.type !== "checkout.session.completed") {
      return new Response("ignored", { status: 200 });
    }

    // A completed checkout can still be unpaid (async/delayed payment methods),
    // so only email someone who has actually paid.
    if (event.data?.object?.payment_status !== "paid") {
      return new Response("not paid", { status: 200 });
    }

    const email = event.data?.object?.customer_details?.email;
    if (!email) {
      return new Response("no customer email", { status: 200 });
    }

    try {
      const key = await licenseKey(await importPrivateKey(env.ED25519_PRIVATE_KEY), email);
      await sendPurchaseEmail(env, email, key);
    } catch (err) {
      // Log so the failure is visible/alertable in Worker observability; a
      // returned 5xx alone is not counted as a Worker error.
      console.error("purchase email send failed:", err.message);
      // Non-2xx so Stripe retries; a duplicate email is acceptable (spec §5).
      return new Response(`email send failed: ${err.message}`, { status: 500 });
    }

    return new Response("ok", { status: 200 });
  },
};

// ── Licence key (Ed25519 signature of the normalized email; base64url) ──
// Same scheme the app validates offline and the sharepad-licenses worker derives.
export function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

export function base64url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function importPrivateKey(pkcs8Base64) {
  const der = Uint8Array.from(atob(pkcs8Base64), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "Ed25519" }, false, ["sign"]);
}

export async function licenseKey(privateKey, email) {
  const message = new TextEncoder().encode(normalizeEmail(email));
  const signature = await crypto.subtle.sign("Ed25519", privateKey, message);
  return base64url(new Uint8Array(signature));
}

export function escapeHtml(text) {
  const map = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
  return text.replace(/[&<>"']/g, (c) => map[c]);
}

// ── Stripe signature verification (Web Crypto; no SDK) ──
export async function verifyStripeSignature(payload, header, secret) {
  if (!secret) return false;

  let timestamp = null;
  const candidates = [];
  for (const part of header.split(",")) {
    const idx = part.indexOf("=");
    if (idx === -1) continue;
    const key = part.slice(0, idx);
    const value = part.slice(idx + 1);
    if (key === "t") timestamp = value;
    else if (key === "v1") candidates.push(value);
  }
  if (!timestamp || candidates.length === 0) return false;

  // Replay guard.
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - Number(timestamp)) > SIG_TOLERANCE_SECONDS) return false;

  const expected = await hmacSha256Hex(secret, `${timestamp}.${payload}`);
  return candidates.some((candidate) => timingSafeEqualHex(expected, candidate));
}

async function hmacSha256Hex(secret, message) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqualHex(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ── Email ──
async function sendPurchaseEmail(env, to, key) {
  const downloadUrl = env.DOWNLOAD_URL || "https://sharepad.co/thanks-a7f3c92b.html?owner";
  const recoverUrl = env.RECOVER_URL || "https://sharepad-licenses.jonyardley.workers.dev/recover";
  const from = env.EMAIL_FROM || "SharePad <hello@sharepad.co>";

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to,
      subject: "Your SharePad licence and download",
      html: purchaseEmailHtml(downloadUrl, to, key, recoverUrl),
      text: purchaseEmailText(downloadUrl, to, key, recoverUrl),
    }),
  });

  if (!response.ok) {
    throw new Error(`Resend ${response.status}: ${await response.text()}`);
  }
}

// Email-safe by construction: Spark/Outlook drop rgba(), styled <a> buttons,
// <pre>, and div cards that Gmail tolerates — hence tables, a bgcolor button, and hex.
export function purchaseEmailHtml(downloadUrl, email, key, recoverUrl) {
  const address = escapeHtml(normalizeEmail(email));
  const href = escapeHtml(downloadUrl);
  const recover = escapeHtml(recoverUrl);
  const font = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";
  const mono = "'SF Mono',ui-monospace,SFMono-Regular,Menlo,Consolas,monospace";
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="color-scheme" content="light only">
  <meta name="supported-color-schemes" content="light">
</head>
<body style="margin:0;padding:0;background:#F3F4FB;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F3F4FB;">
    <tr>
      <td align="center" style="padding:32px 16px;">
        <table role="presentation" width="520" cellpadding="0" cellspacing="0" border="0" style="width:520px;max-width:100%;">
          <tr>
            <td style="background:#FFFFFF;border:1px solid #E6E7F2;border-radius:24px;padding:36px 32px;font-family:${font};color:#181C44;">
              <h1 style="font-size:22px;line-height:1.25;margin:0 0 12px;color:#181C44;">Thanks for buying SharePad</h1>
              <p style="font-size:15px;line-height:1.6;color:#4A4F78;margin:0 0 24px;">
                Your download is ready whenever you need it, including if you ever switch Macs.
                Keep this email; the link below always points at the latest version.
              </p>
              <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" bgcolor="#3E4CB3" style="border-radius:999px;">
                    <a href="${href}" style="display:inline-block;color:#FFFFFF;text-decoration:none;font-family:${font};font-weight:600;font-size:15px;line-height:1;padding:15px 28px;border-radius:999px;">Download SharePad</a>
                  </td>
                </tr>
              </table>
              <p style="font-size:13px;line-height:1.6;color:#4A4F78;margin:24px 0 0;">
                Signed &amp; notarised by Apple. Open the DMG, drag SharePad to Applications,
                and it lives in your menu bar. Plug in your iPad over USB and the share window
                appears automatically.
              </p>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:28px;">
                <tr><td style="border-top:1px solid #E6E7F2;font-size:0;line-height:0;height:1px;">&nbsp;</td></tr>
              </table>
              <p style="font-size:15px;line-height:1.6;color:#181C44;margin:24px 0 12px;font-weight:600;">Your licence</p>
              <p style="font-size:13px;line-height:1.6;color:#4A4F78;margin:0 0 4px;">Email: <span style="font-family:${mono};color:#181C44;">${address}</span></p>
              <p style="font-size:13px;line-height:1.6;color:#4A4F78;margin:0 0 6px;">Key:</p>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;">
                <tr>
                  <td style="background:#F3F4FB;border-radius:10px;padding:12px 14px;font-family:${mono};font-size:12px;line-height:1.5;color:#181C44;word-break:break-all;">${escapeHtml(key)}</td>
                </tr>
              </table>
              <p style="font-size:13px;line-height:1.6;color:#4A4F78;margin:0 0 12px;">
                In SharePad's menu bar, choose "Enter licence..." and paste both. It takes
                effect straight away and works offline &mdash; SharePad never checks in with a server.
              </p>
              <p style="font-size:13px;line-height:1.6;color:#4A4F78;margin:0;">
                Lost your key later? Get it again anytime at
                <a href="${recover}" style="color:#3E4CB3;">recover your licence</a>
                with the email above &mdash; no account, no sign-in.
              </p>
              <p style="font-size:13px;line-height:1.6;color:#4A4F78;margin:24px 0 0;">
                SharePad is open source (GPLv3) with automatic updates for life. Need a hand?
                Just reply to this email.
              </p>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:20px 0 0;font-family:${font};font-size:12px;color:#4A4F78;">
              <a href="https://sharepad.co" style="color:#3E4CB3;text-decoration:none;">sharepad.co</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

export function purchaseEmailText(downloadUrl, email, key, recoverUrl) {
  const address = normalizeEmail(email);
  return `Thanks for buying SharePad

Your download is ready whenever you need it, including if you ever switch Macs.
Keep this email; the link below always points at the latest version.

Download SharePad: ${downloadUrl}

Signed & notarised by Apple. Open the DMG, drag SharePad to Applications, and it
lives in your menu bar. Plug in your iPad over USB and the share window appears
automatically.

Your licence
Email: ${address}
Key:
${key}

In SharePad's menu bar, choose "Enter licence..." and paste both. It takes effect
straight away and works offline -- SharePad never checks in with a server.

Lost your key later? Get it again anytime at ${recoverUrl} with the email above
-- no account, no sign-in.

SharePad is open source (GPLv3) with automatic updates for life. Need a hand?
Just reply to this email.

sharepad.co`;
}
