// 전중배 푸시 전송 Edge Function.
// notifications INSERT 웹훅 → 해당 recipient 의 device_tokens 로 FCM v1 발송.
// 시크릿: FIREBASE_SERVICE_ACCOUNT(서비스계정 JSON). 런타임 주입: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

function b64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "").replace(/\s+/g, "");
  const raw = atob(body);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

// 서비스계정 → FCM scope OAuth2 access token.
async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error("oauth: " + JSON.stringify(json));
  return json.access_token;
}

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    const rec = payload.record ?? payload; // DB 웹훅이면 record, 직접 호출이면 본문
    const recipientId: string = rec.recipient_id;
    const title: string = rec.title ?? "전중배";
    const body: string = rec.body ?? "";
    if (!recipientId) return new Response("no recipient", { status: 400 });

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sa: ServiceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);

    // 수신자 디바이스 토큰 조회(service_role, RLS 우회).
    const dtRes = await fetch(
      `${SUPABASE_URL}/rest/v1/device_tokens?select=token&user_id=eq.${recipientId}`,
      { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` } },
    );
    const tokens: { token: string }[] = await dtRes.json();
    if (!Array.isArray(tokens) || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: "no tokens" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken(sa);
    const fcmUrl =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    let sent = 0;
    const errors: string[] = [];
    for (const { token } of tokens) {
      const r = await fetch(fcmUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data: rec.data
              ? Object.fromEntries(
                Object.entries(rec.data).map(([k, v]) => [k, String(v)]),
              )
              : {},
            android: { priority: "high" },
          },
        }),
      });
      if (r.ok) sent++;
      else errors.push((await r.text()).slice(0, 120));
    }
    return new Response(JSON.stringify({ sent, total: tokens.length, errors }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
