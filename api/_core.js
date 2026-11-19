// 공용 API 로직: 로컬 server.js 와 Vercel 함수(api/*.js)가 함께 사용한다.
// '_' 로 시작하는 파일은 Vercel 이 함수로 배포하지 않는다.
// API 키는 서버(환경변수)에만 있고 브라우저/앱으로는 절대 내려가지 않는다.

const MODEL = process.env.OPENAI_MODEL || 'gpt-4o-mini';
const key = () => process.env.OPENAI_API_KEY || '';
// 키 모양만 확인 (키 내용은 절대 출력하지 않음)
export const keyOk = () => /^sk-[\w-]{20,}$/.test(key());

const fail = c => Object.assign(new Error(c), { code: c });          // 클라이언트로 보낼 오류 코드
const hide = s => String(s).replace(/sk-[\w\-*.]+/g, 'sk-***').replace(/AIza[\w-]+/g, 'AIza***'); // 로그에 키가 섞여도 가림
const mapsKey = () => process.env.GOOGLE_MAPS_API_KEY || '';

// OpenAI Chat Completions 호출 → JSON 객체로 반환
// (같은 계정에서 사진 분석이 Responses API 보다 약 1.7배 빨라 이 방식을 쓴다)
// content 항목: {type:'input_text', text} | {type:'input_image', image_url, detail?}
const toChat = c => c.type === 'input_image'
  ? { type: 'image_url', image_url: { url: c.image_url, ...(c.detail ? { detail: c.detail } : {}) } }
  : { type: 'text', text: c.text };
async function ask(content) {
  if (!key()) throw fail('no_api_key');
  let r;
  try {
    r = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + key() },
      // store:false — OpenAI 에 요청·응답(사진 정보)을 저장하지 않는다
      body: JSON.stringify({ model: MODEL, messages: [{ role: 'user', content: content.map(toChat) }], response_format: { type: 'json_object' }, store: false }),
      signal: AbortSignal.timeout(60000), // 60초 넘으면 중단
    });
  } catch (e) { throw fail(e.name === 'TimeoutError' ? 'timeout' : 'openai_unreachable'); }
  if (!r.ok) { console.error('OpenAI 오류', r.status, hide((await r.text()).slice(0, 300))); throw fail('openai_' + r.status); }
  const j = await r.json();
  const text = j.choices?.[0]?.message?.content || '';
  try { return JSON.parse(text); } catch { console.error('AI 응답이 JSON이 아님:', hide(text.slice(0, 200))); throw fail('bad_ai_json'); }
}

// 프롬프트는 서버가 소유 (프론트에서 마음대로 못 바꿈)
const ANALYZE = '이 사진을 분석해 JSON만 출력(이름·신원 추측 금지): {"caption":"한 문장","food":["음식"],"place":"장소 유형","people":"인원수·옷차림 등 특성","background":"배경","weather":"날씨","time":"낮/저녁/밤/알 수 없음"}';
const searchPrompt = (db, hist, extra = '') =>
  '너는 스마트 갤러리 기억 검색 엔진이다. 사진 DB에서 사용자의 흐릿한 기억과 대화 기록에 가장 맞는 사진을 찾아라.\nDB:' + JSON.stringify(db) +
  '\n대화:' + JSON.stringify(hist) +
  '\n규칙: 대화에 이미 나온 질문과 같거나 비슷한 주제(건너뛴 질문 포함)는 절대 다시 묻지 마라. 더 이상 가를 새 질문이 없거나 후보가 뚜렷하면 question을 null로 반환하라.' +
  (extra ? '\n' + extra : '') +
  '\nJSON만 출력: {"ranked":[{"id":숫자,"score":0-100,"matched":["맞은 단서"],"missing":["확인 안 된 단서"]}],"question":{"text":"아직 묻지 않은, 후보를 가장 잘 가르는 질문 하나","options":["선택지 2~3개"]} 또는 null}';

const normQ = s => String(s || '').replace(/[\s?!.,'"`~]/g, '').toLowerCase();
const askedQuestions = hist => hist.map(h => String(h).match(/^Q:\s*(.+?)\s*\/\s*A:/)?.[1]).filter(Boolean);
const isDupQ = (q, asked) => {
  const n = normQ(q?.text);
  return !n || asked.some(a => normQ(a) === n);
};

// IP당 분당 요청 제한 (서버리스에서는 인스턴스별로 집계됨)
// 사진 분석은 앱이 여러 장을 동시에 보내므로 120회, 나머지(검색·앨범 등)는 30회
const LIMITS = { analyze: 120 };
const hits = new Map();
const limited = (ip, route) => {
  const k = route + ':' + ip, n = Date.now(), a = (hits.get(k) || []).filter(t => n - t < 60000);
  a.push(n); hits.set(k, a);
  return a.length > (LIMITS[route] || 30);
};

const MAX_BODY = 6e6;
// Vercel 은 JSON 본문을 req.body 로 미리 파싱해 준다. 로컬(node:http)은 스트림을 직접 읽는다.
const readBody = req => {
  if (req.body !== undefined) {
    if (typeof req.body === 'string') return Promise.resolve(JSON.parse(req.body || '{}'));
    if (Buffer.isBuffer(req.body)) return Promise.resolve(JSON.parse(req.body.toString() || '{}'));
    return Promise.resolve(req.body || {});
  }
  return new Promise((ok, no) => {
    let b = '';
    req.on('data', c => { b += c; if (b.length > MAX_BODY) { no(new Error('too big')); req.destroy(); } });
    req.on('end', () => { try { ok(JSON.parse(b || '{}')); } catch (e) { no(e); } });
  });
};
const send = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
const clientIp = req => String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() || req.socket?.remoteAddress || 'unknown';

async function analyze(b) {
  if (typeof b.image !== 'string' || !b.image.startsWith('data:image/')) return [400, { error: 'bad_image' }];
  // detail:'low' — 모델이 512px 한 장으로 본다 (앱도 512px로 보냄). 빠르고 토큰이 적다.
  return [200, await ask([{ type: 'input_text', text: ANALYZE }, { type: 'input_image', image_url: b.image, detail: 'low' }])];
}

// wantQuestion: 사용자가 '질문 한 번 더하기'를 눌렀을 때 — 질문 개수 제한 없이 반드시 하나 만들도록 요청
const WANT_Q = '사용자가 추가 질문을 요청했다. 현재 상위 후보들을 가장 잘 구분하는 새 질문을 반드시 하나 만들어라(question을 null로 두지 마라).';

async function search(b) {
  if (!Array.isArray(b.db) || !Array.isArray(b.hist) || b.db.length > 300) return [400, { error: 'bad_request' }];
  const db = b.db.map(({ thumb, e, ...d }) => d); // 썸네일은 모델에 보내지 않음
  const hist = b.hist.slice(-12);
  const want = b.wantQuestion === true;
  const asked = askedQuestions(hist);
  let result = await ask([{ type: 'input_text', text: searchPrompt(db, hist, want ? WANT_Q : '') }]);
  if (!want && asked.length >= 5) {
    result.question = null;
  } else if (result.question && isDupQ(result.question, asked)) {
    result = await ask([{ type: 'input_text', text: searchPrompt(db, hist, (want ? WANT_Q + ' ' : '') + '방금 중복 질문을 냈다. 이미 물은 질문(' + asked.join(' | ') + ')을 제외하고 다른 질문을 내' + (want ? '라.' : '거나 null을 반환하라.')) }]);
    if (result.question && isDupQ(result.question, asked)) result.question = null;
  }
  return [200, result];
}

// AI 대화형 앨범: 자연어 요청에 맞는 사진을 DB에서 모두 고르고, 카테고리도 하나 추천한다
const DEFAULT_CATS = [
  { id: 'memories', label: '추억', hint: '여행, 가족, 친구, 일상, 기념일' },
  { id: 'inspiration', label: '취향', hint: '네일, 패션, 쇼핑, 위시리스트, 개인적인 디자인 레퍼런스' },
  { id: 'projects', label: '작업', hint: '업무 자료, 과제, 디자인 및 프로젝트 레퍼런스' },
];
const cleanCats = raw => {
  const list = (Array.isArray(raw) ? raw : []).slice(0, 20)
    .map(c => ({ id: String(c?.id || '').slice(0, 40), label: String(c?.label || '').slice(0, 20), hint: String(c?.hint || '').slice(0, 80) }))
    .filter(c => c.id && c.label);
  return list.length ? list : DEFAULT_CATS;
};
const albumPrompt = (db, request, cats) =>
  '너는 스마트 갤러리의 앨범 큐레이터다. 사용자의 앨범 요청에 맞는 사진을 DB에서 모두 골라라. ' +
  '요청의 포함 조건과 제외 조건(예: "음식 사진은 빼고")을 모두 지켜라. 확실히 맞지 않는 사진은 넣지 마라.' +
  '\n그리고 요청과 고른 사진 내용을 보고 아래 카테고리 중 가장 알맞은 것 하나의 id를 골라라.' +
  '\n카테고리:' + JSON.stringify(cats) +
  '\nDB:' + JSON.stringify(db) + '\n요청:' + JSON.stringify(request) +
  '\nJSON만 출력: {"title":"15자 이내 앨범 이름","ids":[고른 사진 id 숫자들],"category":"카테고리 id"}';

async function album(b) {
  const request = typeof b.request === 'string' ? b.request.trim().slice(0, 500) : '';
  if (!request || !Array.isArray(b.db) || b.db.length > 300) return [400, { error: 'bad_request' }];
  const db = b.db.map(({ thumb, e, ...d }) => d);
  const known = new Set(db.map(d => d.id));
  const cats = cleanCats(b.categories);
  const r = await ask([{ type: 'input_text', text: albumPrompt(db, request, cats) }]);
  const ids = [...new Set((Array.isArray(r.ids) ? r.ids : []).map(Number))].filter(id => known.has(id));
  const title = String(r.title || '').trim().slice(0, 30) || request.slice(0, 15);
  const category = cats.some(c => c.id === r.category) ? r.category : null;
  return [200, { title, ids, category }];
}

// 사진 GPS 좌표 → 구글 지도 기준 지역명 (예: "서울특별시 성동구 성수동2가")
// 키는 서버 환경변수 GOOGLE_MAPS_API_KEY 에만 둔다.
const PLACE_TYPES = ['administrative_area_level_1', 'locality', 'sublocality_level_1', 'sublocality_level_2'];
async function place(b) {
  const lat = Number(b.lat), lng = Number(b.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return [400, { error: 'bad_request' }];
  if (!mapsKey()) return [503, { error: 'no_maps_key' }];
  const url = 'https://maps.googleapis.com/maps/api/geocode/json?language=ko&latlng=' + lat.toFixed(6) + ',' + lng.toFixed(6) + '&key=' + encodeURIComponent(mapsKey());
  let r;
  try { r = await fetch(url, { signal: AbortSignal.timeout(10000) }); } catch (e) { throw fail(e.name === 'TimeoutError' ? 'timeout' : 'maps_unreachable'); }
  const j = await r.json().catch(() => ({}));
  if (j.status === 'ZERO_RESULTS') return [200, { name: null }];
  if (j.status !== 'OK') { console.error('Google 지오코딩 오류', j.status, hide(j.error_message || '')); throw fail('maps_' + String(j.status || r.status).toLowerCase()); }
  // 첫 결과의 주소 구성요소에서 시·도 → 시·군·구 → 동 순서로 (중복 제외)
  const comps = j.results?.[0]?.address_components || [];
  const parts = [];
  for (const t of PLACE_TYPES) {
    const c = comps.find(c => c.types?.includes(t));
    if (c && !parts.includes(c.long_name)) parts.push(c.long_name);
  }
  const name = parts.join(' ') || String(j.results?.[0]?.formatted_address || '').replace(/^대한민국\s*/, '') || null;
  return [200, { name }];
}

const POST_ROUTES = { analyze, search, album, place };

// route: 'health' | 'analyze' | 'search' | 'album' | 'place' (그 외는 404)
export async function handleApi(req, res, route) {
  try {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
    if (route === 'health') {
      if (req.method !== 'GET') return send(res, 405, { error: 'method_not_allowed' });
      return send(res, 200, { ok: true, key: keyOk(), model: MODEL, maps: !!mapsKey() });
    }
    const fn = POST_ROUTES[route];
    if (!fn) return send(res, 404, { error: 'not_found' });
    if (req.method !== 'POST') return send(res, 405, { error: 'method_not_allowed' });
    if (limited(clientIp(req), route)) return send(res, 429, { error: 'rate_limited' });
    const [code, out] = await fn(await readBody(req));
    return send(res, code, out);
  } catch (e) {
    const c = e.code || (e.message === 'too big' ? 'too_big' : e instanceof SyntaxError ? 'bad_request' : 'server_error');
    console.error('요청 실패:', c, hide(e.message));
    try { send(res, c === 'too_big' ? 413 : c === 'bad_request' ? 400 : e.code ? 502 : 500, { error: c }); } catch {}
  }
}
