// 전중배 주소→좌표 지오코딩 Edge Function.
// 카카오 로컬 REST API 사용. REST 키는 시크릿(KAKAO_REST_KEY)으로만 보관(클라이언트 비노출).
// 입력: { query: "서울 강남구 역삼동 123-4" }  →  출력: { lat, lng, matched } (없으면 lat/lng null)

const KAKAO = "https://dapi.kakao.com/v2/local/search";

async function kakao(path: string, query: string, key: string) {
  const res = await fetch(`${KAKAO}/${path}?query=${encodeURIComponent(query)}&size=1`, {
    headers: { Authorization: `KakaoAK ${key}` },
  });
  if (!res.ok) return null;
  const json = await res.json();
  const doc = json.documents?.[0];
  if (!doc) return null;
  // 주소 검색: x=lng, y=lat (문자열) / 키워드 검색도 동일 키.
  const lat = parseFloat(doc.y);
  const lng = parseFloat(doc.x);
  if (Number.isFinite(lat) && Number.isFinite(lng)) {
    return { lat, lng, matched: doc.address_name ?? doc.place_name ?? query };
  }
  return null;
}

Deno.serve(async (req: Request) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { query } = await req.json();
    if (!query || typeof query !== "string") {
      return new Response(JSON.stringify({ error: "query required" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }
    const key = Deno.env.get("KAKAO_REST_KEY");
    if (!key) {
      return new Response(JSON.stringify({ error: "KAKAO_REST_KEY 미설정" }), {
        status: 500,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }
    // ① 주소 검색 → ② 실패 시 키워드(장소명) 검색 폴백.
    const result = (await kakao("address.json", query, key)) ??
      (await kakao("keyword.json", query, key));
    return new Response(
      JSON.stringify(result ?? { lat: null, lng: null, matched: null }),
      { headers: { ...cors, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
