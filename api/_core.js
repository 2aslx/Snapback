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
// temperature: 0(+ seed 고정)이면 같은 입력에 (거의) 같은 답 — 일관성이 필요한 곳(앨범)에서 쓴다. 생략하면 OpenAI 기본값.
async function ask(content, { temperature } = {}) {
  if (!key()) throw fail('no_api_key');
  let r;
  try {
    r = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + key() },
      // store:false — OpenAI 에 요청·응답(사진 정보)을 저장하지 않는다
      body: JSON.stringify({ model: MODEL, messages: [{ role: 'user', content: content.map(toChat) }], response_format: { type: 'json_object' }, store: false, ...(temperature === undefined ? {} : { temperature, seed: 7 }) }),
      signal: AbortSignal.timeout(60000), // 60초 넘으면 중단
    });
  } catch (e) { throw fail(e.name === 'TimeoutError' ? 'timeout' : 'openai_unreachable'); }
  if (!r.ok) { console.error('OpenAI 오류', r.status, hide((await r.text()).slice(0, 300))); throw fail('openai_' + r.status); }
  const j = await r.json();
  const text = j.choices?.[0]?.message?.content || '';
  try { return JSON.parse(text); } catch { console.error('AI 응답이 JSON이 아님:', hide(text.slice(0, 200))); throw fail('bad_ai_json'); }
}

// 프롬프트는 서버가 소유 (프론트에서 마음대로 못 바꿈)
// ── 사진 분석 v2 ─────────────────────────────────────────────
// 시각 · 의미 · 정보 추출 · 라이프로깅 4가지 관점. 기존 필드(caption·food·place·people·background·weather·time)도
// 함께 채워 검색·앨범·관련된 추억이 그대로 동작한다. 특정 이미지·키워드를 하드코딩하지 않는다.
const ANALYSIS_VERSION = 2;
const ANALYZE =
  '이 이미지를 분석해 JSON만 출력하라.\n' +
  '[관점]\n' +
  '1) 시각: 핵심 피사체와 구체적 시각 특징(예: 디자인·색상·패턴, 의류 종류·핏, 공간·가구), 부수적 객체.\n' +
  '2) 의미: 이미지 유형(image_type), 출처 플랫폼(확인될 때만), 상위/세부 카테고리, 핵심 주제, 내용 요약.\n' +
  '3) 정보 추출: 이미지 속 핵심 글자(extracted_text)와 유형에 맞는 구조화 정보(structured_data).\n' +
  '4) 라이프로깅: 사용자가 이 이미지를 저장한 목적 추정(확정 아님), 의미 기반 검색 키워드, 어울리는 기록 종류.\n' +
  '[규칙]\n' +
  '- 스크린샷·문서는 좋아요·댓글·공유·구독 버튼, 상태 표시줄 같은 화면 UI 요소를 무시하고 본문·제품명·문서 내용을 우선한다.\n' +
  '- place 는 실제로 촬영된 물리적 장소 유형(카페, 해변, 교실 등)만 쓴다. 스크린샷·문서·디지털 이미지는 place 를 빈 문자열로 둔다. 유튜브·인스타그램 같은 플랫폼은 place 가 아니라 source_platform 이다.\n' +
  '- 이미지에서 확인되지 않는 가격·브랜드·제품명·수치는 절대 만들어 내지 않는다. 가려지거나 흐린 글자는 "(불확실)"을 붙인다.\n' +
  '- 건강·의료 문서는 적힌 항목·수치·단위만 옮기고 의학적 판단·진단·조언을 쓰지 않는다.\n' +
  '- 사람의 이름·신원 추측, 문서에 적힌 성명·생년월일·주민등록번호·전화번호·계좌번호·주소·이메일 같은 개인 식별 정보는 어디에도(extracted_text·structured_data·caption 포함) 적지 않는다.\n' +
  '- source_platform 은 로고·앱 이름·고유한 화면 구성으로 분명할 때만 적고, 짐작하지 않는다(애매하면 빈 문자열).\n' +
  '- 보이지 않거나 판단할 수 없는 항목은 "없음"·"알 수 없음" 대신 빈 문자열("") 또는 빈 배열로 둔다.\n' +
  '- 사람이 보일 때만 people 을 쓴다. 사진의 주인공(가장 크게·앞에 보이는 사람)을 먼저 "주인공: …"으로, 뒤쪽·가장자리 인물은 "배경: …"으로 구분한다. ' +
  '옷은 "색상 + 종류 + 보이는 글자·무늬·로고"로 구체적으로(예: 빨간 축구 유니폼, 가슴에 영문 로고), 손에 든 물건·하는 행동도 함께 적는다. 신원·이름은 추측하지 않는다. ' +
  '형식: "주인공: 인원, 색상 옷 종류(보이는 글자·무늬), 들고 있는 물건·행동 / 배경: 인원, 색상 옷 종류" (사진에 실제로 보이는 것만, 예시 문구를 그대로 쓰지 않는다).\n' +
  '- structured_data 의 키는 한국어로, 유형에 맞게 자유롭게 구성한다(예: 추천 제품 목록과 추천 이유, 시험명·등급·발급기관, 항목·수치·단위, 재료·조리 순서).\n' +
  '[출력 JSON]\n' +
  '{"image_type":"photo|screenshot|document|shopping_list|recipe|certificate|receipt|health_report|ticket|menu|chat|note|artwork|기타 영어 소문자 유형",' +
  '"source_platform":"확인될 때만, 아니면 빈 문자열",' +
  '"semantic_category":["상위 카테고리","세부 카테고리"],' +
  '"main_topic":"핵심 주제 한 구절",' +
  '"content_summary":"주요 내용 1~2문장",' +
  '"extracted_text":"핵심 글자 발췌(최대 300자)",' +
  '"structured_data":{},' +
  '"inferred_purpose":"저장 목적 추정 한 문장",' +
  '"search_keywords":["의미 기반 검색어·관련 표현 5~10개"],' +
  '"suggested_record_type":"moment|place|taste|shopping|document|info",' +
  '"caption":"이미지 내용 한 문장(항상 작성)",' +
  '"food":["보이는 음식"],"place":"촬영 장소 유형 또는 빈 문자열","people":"사람이 보일 때만: 주인공: … / 배경: …",' +
  '"background":"배경·부수적 객체와 핵심 피사체의 구체적 시각 특징","weather":"날씨","time":"낮/저녁/밤 중 하나 또는 빈 문자열"}';

// 글자가 많은 유형: 1차(512px·low) 뒤 고해상도로 한 번 더 분석할 대상
const TEXT_DENSE = new Set(['screenshot', 'document', 'shopping_list', 'recipe', 'certificate', 'receipt', 'health_report', 'ticket', 'menu', 'chat', 'note']);
const RECORD_TYPES = ['moment', 'place', 'taste', 'shopping', 'document', 'info'];
const PLATFORM_WORDS = /(소셜|SNS|인스타|유튜브|틱톡|페이스북|트위터|온라인|웹사이트|앱 화면|화면|스크린샷|social|instagram|youtube|tiktok)/i;

// structured_data 를 JSON 길이 상한 안으로 줄인다 (기기 저장·검색 요청 크기 보호)
function capJson(v, max = 1500, depth = 0) {
  const fits = x => JSON.stringify(x).length <= max;
  if (v == null) return {};
  if (typeof v === 'string') return v.slice(0, 200);
  if (typeof v !== 'object') return v;
  if (depth > 3) return Array.isArray(v) ? [] : {};
  let out = Array.isArray(v) ? v.slice(0, 12).map(x => capJson(x, max, depth + 1))
    : Object.fromEntries(Object.entries(v).slice(0, 16).map(([k, x]) => [String(k).slice(0, 30), capJson(x, max, depth + 1)]));
  while (!fits(out)) {
    if (Array.isArray(out)) { if (!out.length) break; out = out.slice(0, out.length - 1); }
    else { const ks = Object.keys(out); if (!ks.length) break; delete out[ks[ks.length - 1]]; }
  }
  return out;
}

// 개인 식별 정보 제거 (프롬프트로 막아도 새어 나올 수 있어 서버에서 한 번 더)
// 키 이름으로 판단: '이름'·'name' 은 제품 이름일 수 있어 정확히 그 단어일 때만, 나머지는 포함되면 제거
const PII_KEY = /(성명|생년월일|주민|전화|연락처|휴대폰|핸드폰|계좌|주소|이메일|e-?mail|birth|phone|mobile|address|account|ssn|응시자|수험자|소유자|holder)/i;
// '이름'·'name' 은 목록 안에선 제품 이름일 수 있어, 문서 맨 위 단계(소지자 이름)에서만 개인 정보로 본다
const NAME_KEY = /^\s*(이름|name|full ?name)\s*$/i;
const isPiiKey = (k, depth) => PII_KEY.test(k) || (depth === 0 && NAME_KEY.test(k));
function scrubPII(text) {
  return String(text)
    .replace(/(성\s*명|생년월일|주민등록번호|전화번호|연락처|휴대폰|계좌번호|주\s*소|이메일)\s*[:：]?\s*[^\s,·|/]+/g, '')
    .replace(/\d{6}\s*-\s*[1-4]\d{6}/g, '')                        // 주민등록번호
    .replace(/(01[016789]|0\d{1,2})[-.\s]?\d{3,4}[-.\s]?\d{4}/g, '') // 전화번호
    .replace(/[\w.+-]+@[\w-]+\.[\w.]+/g, '')                          // 이메일
    .replace(/\b\d{2,6}-\d{2,6}-\d{2,8}(-\d{1,6})?\b/g, '')           // 계좌번호 형태
    .replace(/\s{2,}/g, ' ')
    .trim();
}
/// structured_data 에서 개인 정보 키에 들어 있던 값들 (예: 성명 → '김테스트') — 다른 글에서도 지우기 위해
function piiValues(v, out = new Set(), depth = 0) {
  if (Array.isArray(v)) v.forEach(x => piiValues(x, out, depth + 1));
  else if (v && typeof v === 'object') {
    for (const [k, x] of Object.entries(v)) {
      if (isPiiKey(k, depth) && (typeof x === 'string' || typeof x === 'number') && String(x).trim().length >= 2) out.add(String(x).trim());
      else piiValues(x, out, depth + 1);
    }
  }
  return out;
}

function scrubData(v, depth = 0) {
  if (typeof v === 'string') return scrubPII(v);
  if (Array.isArray(v)) return v.map(x => scrubData(x, depth + 1));
  if (v && typeof v === 'object') {
    return Object.fromEntries(Object.entries(v).filter(([k]) => !isPiiKey(k, depth)).map(([k, x]) => [k, scrubData(x, depth + 1)]));
  }
  return v;
}

function normalizeAnalysis(r) {
  // 개인 정보 값(성명 등)을 모아 두고 캡션·요약·발췌·키워드에서도 지운다
  const pii = [...piiValues(r.structured_data)];
  const strip = t => pii.reduce((acc, v) => acc.split(v).join(''), t).replace(/\s{2,}/g, ' ').replace(/^[의\s]+/, '').trim();
  const str = (v, n) => (typeof v === 'string' ? strip(v.trim()).slice(0, n) : '');
  const arr = (v, n, each) => (Array.isArray(v) ? v : typeof v === 'string' && v ? [v] : [])
    .map(x => str(String(x), each)).filter(Boolean).slice(0, n);
  const imageType = (str(r.image_type, 30).toLowerCase().replace(/[^a-z_]/g, '') || 'photo');
  const source = str(r.source_platform, 40);
  let place = str(r.place, 60);
  // 플랫폼·화면을 촬영 장소로 적은 경우 비운다 ('소셜 미디어'는 장소가 아님)
  if (imageType !== 'photo' && (TEXT_DENSE.has(imageType) || source)) place = '';
  if (PLATFORM_WORDS.test(place)) place = '';
  const rec = str(r.suggested_record_type, 20);
  return {
    analysis_version: ANALYSIS_VERSION,
    image_type: imageType,
    text_dense: TEXT_DENSE.has(imageType),
    source_platform: source,
    semantic_category: arr(r.semantic_category, 4, 30),
    main_topic: str(r.main_topic, 80),
    content_summary: scrubPII(str(r.content_summary, 300)),
    extracted_text: scrubPII(str(r.extracted_text, 600)),
    structured_data: capJson(scrubData(r.structured_data && typeof r.structured_data === 'object' ? r.structured_data : {})),
    inferred_purpose: str(r.inferred_purpose, 120),
    search_keywords: arr(r.search_keywords, 12, 24),
    suggested_record_type: RECORD_TYPES.includes(rec) ? rec : 'moment',
    caption: scrubPII(str(r.caption, 160)),
    food: arr(r.food, 8, 30),
    place,
    people: str(r.people, 220),
    background: str(r.background, 200),
    weather: str(r.weather, 30),
    time: ['낮', '저녁', '밤', '아침', '오후', '새벽'].includes(str(r.time, 10)) ? str(r.time, 10) : '',
  };
}

const searchPrompt = (db, hist, extra = '') =>
  '너는 스마트 갤러리 기억 검색 엔진이다. 사진 DB에서 사용자의 흐릿한 기억과 대화 기록에 가장 맞는 사진을 찾아라. ' +
  'rk 는 사용자가 예전에 이 사진을 직접 찾아 "맞아요"로 확인한 키워드, rq 는 그때 쓴 기억 문장이다(사용자가 확인한 사실이므로 강한 단서로 본다). addr 는 촬영 위치의 시·구·동 주소다. 신촌·홍대 같은 생활권 지명은 해당 행정 주소와 연결해 판단하라.\nDB:' + JSON.stringify(db) +
  '\n대화:' + JSON.stringify(hist) +
  '\n규칙: 대화에 이미 나온 질문과 같거나 비슷한 주제(건너뛴 질문 포함)는 절대 다시 묻지 마라. 더 이상 가를 새 질문이 없거나 후보가 뚜렷하면 question을 null로 반환하라.' +
  (extra ? '\n' + extra : '') +
  '\n대화의 "Q: … / A: …" 에서 A 는 사용자가 확인해 준 사실이다. 답과 맞는 사진은 점수를 크게 올리고, 답과 어긋나는 사진(예: 답이 "비"인데 weather 가 흐림·맑음)은 크게 낮춰라. 답이 "모르겠어요"·건너뛰기면 무시하라.' +
  '\nranked 에는 기억과 관련 있는 사진을 점수 높은 순으로 최대 30개 넣어라.' +
  '\nmatched 에는 기억과 맞은 단서를 그 사진 정보에서 **글자 그대로** 복사한 낱말로 적어라(사진 정보에 없는 말은 쓰지 마라).' +
  '\nJSON만 출력: {"ranked":[{"id":숫자,"score":0-100,"matched":["맞은 단서"],"missing":["확인 안 된 단서"]}],"question":{"text":"아직 묻지 않은, 후보를 가장 잘 가르는 질문 하나","options":["선택지 2~3개"]} 또는 null}';

// 검색·앨범·제안 요청용 사진 정보: 썸네일·구조화 데이터 제외, 긴 글자는 잘라 요청 크기·토큰을 일정하게
const slimPhoto = ({ thumb, e, data, ...d }) => {
  if (typeof d.text === 'string' && d.text.length > 150) d.text = d.text.slice(0, 150);
  if (typeof d.summary === 'string' && d.summary.length > 160) d.summary = d.summary.slice(0, 160);
  if (Array.isArray(d.kw)) d.kw = d.kw.slice(0, 8);
  return d;
};

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
  // 기본 detail:'low' (앱이 512px로 보냄, 빠르고 저렴). 글자가 많은 이미지·사용자의 '다시 분석하기'는
  // 앱이 1280px 이미지와 detail:'high' 를 보내 글자까지 정밀하게 읽는다.
  const detail = b.detail === 'high' ? 'high' : 'low';
  const r = await ask([{ type: 'input_text', text: ANALYZE }, { type: 'input_image', image_url: b.image, detail }]);
  return [200, { ...normalizeAnalysis(r), detail }];
}

// wantQuestion: 사용자가 '질문 한 번 더하기'를 눌렀을 때 — 질문 개수 제한 없이 반드시 하나 만들도록 요청
const WANT_Q = '사용자가 추가 질문을 요청했다. 현재 상위 후보들을 가장 잘 구분하는 새 질문을 반드시 하나 만들어라(question을 null로 두지 마라).';

// 검색 순위를 서버가 일정하게 정한다: AI 점수를 5점 단위로 묶고 → 실제 사진 정보에 있는 단서가 많은 순 → 사진 id 순.
// AI 가 댄 단서 중 그 사진 정보에 없는 것(지어낸 근거)은 하나당 10점 감점, 하나도 없으면 40점 이하로 내린다.
// 사용자가 질문에 답한 낱말이 사진 정보에 있는 사진을 먼저 세운다 (AI 가 답을 놓쳐도 답과 맞는 사진이 위로).
const SEARCH_TOP = 30;  // 앱에 보내는 순위 (앱이 일치도 60~85% 후보를 모두 보여 줌)
const SEARCH_POOL = 30; // 답한 뒤 다시 찾을 후보 범위 (pool)
const photoWords = d => Object.entries(d).filter(([k]) => k !== 'id')
  .flatMap(([, v]) => (Array.isArray(v) ? v : [v])).filter(v => typeof v === 'string').join(' ').toLowerCase();
// 사용자가 질문에 답한 낱말(예: "비", "카페", "밤") — 사진 정보에 그대로 있으면 그 사진을 앞에 세운다
const VAGUE_ANSWER = /^(네|예|응|아니요|아니오|아뇨|모르겠어요|모르겠음|잘 모르겠어요|기억 안 나요|기억이 안 나요|건너뛰기|상관없어요|없음|있음|기타)$/;
const answerWords = hist => hist.map(h => String(h).match(/\/\s*A:\s*(.+)$/)?.[1]?.trim()).filter(a => a && a.length <= 20 && !VAGUE_ANSWER.test(a))
  .map(a => a.toLowerCase());
function rankStable(db, ranked, hist = []) {
  // 예전에 '맞아요'로 확인한 키워드(rk)가 이번 기억 문장·답에 2개 이상 있거나, 같은 문장(rq)이면 앞에 세운다
  const said = hist.map(h => String(h)).join(' ').toLowerCase();
  const firstQ = normQ(hist[0] || '');
  const recallTier = d => {
    if (firstQ && typeof d.rq === 'string' && normQ(d.rq) === firstQ) return 2;
    const n = (Array.isArray(d.rk) ? d.rk : []).filter(k => typeof k === 'string' && k.trim() && said.includes(k.trim().toLowerCase())).length;
    return n >= 2 ? 1 : 0;
  };
  // 후보 중 일부 사진에만 있는 답만 쓴다 (모든 사진에 있거나 아무 데도 없으면 후보를 가르지 못함)
  const texts = db.map(photoWords);
  const answers = answerWords(hist).filter(w => { const n = texts.filter(t => t.includes(w)).length; return n > 0 && n < texts.length; });
  const byId = new Map(db.map(d => [Number(d.id), d]));
  const seen = new Set();
  return (Array.isArray(ranked) ? ranked : []).filter(r => r && byId.has(Number(r.id)) && !seen.has(Number(r.id)) && seen.add(Number(r.id)))
    .map(r => {
      const id = Number(r.id), text = photoWords(byId.get(id));
      const matched = (Array.isArray(r.matched) ? r.matched : []).map(x => String(x).trim()).filter(Boolean).slice(0, 6);
      const real = matched.filter(w => text.includes(w.replace(/^[a-z_]+\s*:\s*/i, '').toLowerCase()));
      let score = Math.max(0, Math.min(100, Math.round(Number(r.score) || 0)));
      score = Math.max(0, score - 10 * (matched.length - real.length)); // 사진 정보에 없는 단서마다 10점 감점
      if (!real.length && score > 40) score = 40;
      const hits = answers.filter(w => text.includes(w)).length; // 사용자의 답과 맞는 개수
      return { id, score, matched, missing: (Array.isArray(r.missing) ? r.missing : []).map(String).slice(0, 6), _real: real.length, _hits: hits, _recall: recallTier(byId.get(id)) };
    })
    .sort((x, y) => y._hits - x._hits || y._recall - x._recall || Math.round(y.score / 5) - Math.round(x.score / 5) || y._real - x._real || x.id - y.id)
    .slice(0, SEARCH_POOL)
    .map(({ _real, _hits, _recall, ...r }) => r);
}

async function search(b) {
  if (!Array.isArray(b.db) || !Array.isArray(b.hist) || b.db.length > 300) return [400, { error: 'bad_request' }];
  const db = b.db.map(slimPhoto); // 썸네일·구조화 정보는 모델에 보내지 않음
  const hist = b.hist.slice(-12);
  const want = b.wantQuestion === true;
  const asked = askedQuestions(hist);
  let result = await ask([{ type: 'input_text', text: searchPrompt(db, hist, want ? WANT_Q : '') }], { temperature: 0 });
  if (!want && asked.length >= 5) {
    result.question = null;
  } else if (result.question && isDupQ(result.question, asked)) {
    result = await ask([{ type: 'input_text', text: searchPrompt(db, hist, (want ? WANT_Q + ' ' : '') + '방금 중복 질문을 냈다. 이미 물은 질문(' + asked.join(' | ') + ')을 제외하고 다른 질문을 내' + (want ? '라.' : '거나 null을 반환하라.')) }], { temperature: 0 });
    if (result.question && isDupQ(result.question, asked)) result.question = null;
  }
  const all = rankStable(db, result.ranked, hist);
  result.ranked = all.slice(0, SEARCH_TOP);
  result.pool = all.map(r => r.id); // 상위 30개 후보 — 앱이 답한 뒤 이 안에서만 다시 찾는다
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
// ── 자연어 앨범 만들기 (3단계) ─────────────────────────────────
// 1) AI 가 요청을 조건으로 해석: 장소는 주소에 나오는 행정 지명으로 펼치고(예: 신촌 → 창천동·신촌동…), 시간은 날짜 범위로
// 2) 서버가 장소(addr)·시간(date)으로 정확히 거른다
// 3) 남은 후보 중 주제·제외 조건에 맞는 사진만 AI 가 고른다
const albumParsePrompt = (request, cats) => {
  const today = new Date().toISOString().slice(0, 10);
  const y = Number(today.slice(0, 4));
  return '스마트 갤러리 앨범 요청을 조건으로 해석해 JSON만 출력하라. 오늘은 ' + today + '.\n' +
    '[규칙]\n' +
    '- place.terms: 요청의 장소를 사진 주소(시·구·동 행정 주소)에 나올 이름으로 펼친다. 생활권 지명은 그 지역의 행정동 이름들로 펼치고 원래 지명도 넣는다. 확실한 이름만 넣고, 구 이름은 그 지명이 확실히 속한 구일 때만 넣는다.\n' +
    '- time: "올여름·작년·10월·이번 달·최근" 같은 시간 표현은 오늘 기준 날짜 범위(from·to, YYYY-MM-DD)로 바꾼다. 여름=6~8월, 봄=3~5월, 가을=9~11월, 겨울=12~2월.\n' +
    '- topic: 무엇을 찍은 사진인지. 요청의 구체적인 대상을 그대로 살리고 넓히지 않는다(예: "패스트푸드" → "햄버거·감자튀김 같은 패스트푸드가 보이는 사진"). ' +
    '"먹은 것·음식"처럼 요청 자체가 넓으면 "음식이 보이는 사진"으로 쓰고 topic_broad=true.\n' +
    '- topic_terms: topic 에 해당하는 구체적인 물건·음식·장소 이름 8~20개. 사진 정보(음식 이름·키워드·캡션)에 그대로 나올 법한 낱말로 쓴다.\n' +
    '- kind: 요청이 구체적인 대상(음식·물건·장소·사람·행동)이면 "object", 분위기·감성·느낌(따뜻한·쓸쓸한·몽환적인·청량한·평화로운 등)이면 "mood".\n' +
    '- kind=mood 일 때: topic 은 그 분위기를 한 구절로, topic_terms 는 빈 배열. mood_cues 에 그 분위기를 만드는 **사진에 실제로 보이는** 단서 8~15개를 쓴다(빛·색·날씨·시간대·장소·사물 이름, 예: 노을, 햇살, 촛불, 비, 안개, 밤, 네온). 형용사·감정 낱말(따뜻한, 감성, 예쁜)은 넣지 않는다. kind=object 면 mood_cues 는 빈 배열.\n' +
    '- exclude: "~은 빼고" 조건, exclude_terms 는 그 대상의 이름들. 요청에 없는 조건은 null·빈 배열·has=false.\n' +
    '[예시]\n' +
    '요청 "작년 여름 신촌에서 먹은 음식" → {"title":"작년 여름 신촌 맛집","place":{"has":true,"terms":["신촌","창천동","신촌동","대현동","대신동","노고산동"]},"time":{"from":"' + (y - 1) + '-06-01","to":"' + (y - 1) + '-08-31"},"topic":"음식이 보이는 사진","kind":"object","topic_broad":true,"topic_terms":[],"mood_cues":[],"exclude":null,"exclude_terms":[],"category":"memories"}\n' +
    '요청 "패스트푸드 사진" → {"title":"패스트푸드 모음","place":{"has":false,"terms":[]},"time":{"from":null,"to":null},"kind":"object","topic":"햄버거·감자튀김 같은 패스트푸드가 보이는 사진","topic_broad":false,"topic_terms":["햄버거","버거","감자튀김","치킨너겟","너겟","피자","핫도그","프라이드치킨"],"exclude":null,"exclude_terms":[],"category":"memories"}\n' +
    '요청 "고기 먹은 사진" → {"title":"고기 모음","place":{"has":false,"terms":[]},"time":{"from":null,"to":null},"kind":"object","topic":"고기 요리가 보이는 사진","topic_broad":false,"topic_terms":["고기","삼겹살","목살","스테이크","갈비","불고기","닭갈비","치킨","보쌈","족발","햄버거"],"exclude":null,"exclude_terms":[],"category":"memories"}\n' +
    '요청 "바다 사진" → {"title":"바다","place":{"has":false,"terms":[]},"time":{"from":null,"to":null},"kind":"object","topic":"바다가 보이는 사진","topic_broad":false,"topic_terms":["바다","해변","해수욕장","파도","해안","바닷가","모래사장"],"exclude":null,"exclude_terms":[],"category":"memories"}\n' +
    '요청 "홍대에서 찍은 사진 중 음식은 빼고" → {"title":"홍대의 순간들","place":{"has":true,"terms":["홍대","서교동","동교동","합정동","연남동"]},"time":{"from":null,"to":null},"kind":"object","topic":null,"topic_broad":false,"topic_terms":[],"exclude":"음식이 주제인 사진","exclude_terms":[],"category":"memories"}\n' +
    '요청 "따뜻한 분위기 사진" → {"title":"따뜻한 순간들","place":{"has":false,"terms":[]},"time":{"from":null,"to":null},"kind":"mood","topic":"따뜻하고 포근한 분위기","topic_broad":false,"topic_terms":[],"mood_cues":["노을","석양","햇살","주황빛","노란 조명","촛불","벽난로","담요","따뜻한 음료","카페","저녁"],"exclude":null,"exclude_terms":[],"category":"memories"}\n' +
    '요청 "쓸쓸한 느낌의 사진" → {"title":"쓸쓸한 장면","place":{"has":false,"terms":[]},"time":{"from":null,"to":null},"kind":"mood","topic":"쓸쓸하고 고요한 분위기","topic_broad":false,"topic_terms":[],"mood_cues":["비","흐림","안개","빈 거리","빈 벤치","홀로","가로등","밤","낙엽","겨울","회색 하늘"],"exclude":null,"exclude_terms":[],"category":"memories"}\n' +
    '카테고리(category 는 이 중 id 하나):' + JSON.stringify(cats) + '\n요청:' + JSON.stringify(request) + '\nJSON:';
};

// 주제는 엄격하게: 사진마다 yes/maybe/no 판정과 '사진 정보에 그대로 있는' 근거 낱말을 받는다.
// 서버가 근거 낱말이 실제로 그 사진 정보에 있는지 확인하므로, AI 가 지어낸 근거로는 앨범에 들어가지 못한다.
const PICK_FIELDS = ['caption', 'background', 'weather', 'time', 'place', 'food', 'people', 'cat', 'topic', 'summary', 'kw', 'type'];
const pickView = d => Object.fromEntries([['id', d.id], ...PICK_FIELDS.filter(k => d[k] != null && d[k] !== '' && !(Array.isArray(d[k]) && !d[k].length)).map(k => [k, d[k]])]);
const pickText = d => PICK_FIELDS.flatMap(k => (Array.isArray(d[k]) ? d[k] : [d[k]])).filter(v => typeof v === 'string').join(' ').toLowerCase();
const grounded = (d, words) => {
  const text = pickText(d);
  return (Array.isArray(words) ? words : []).map(w => String(w).replace(/^[a-z_]+\s*:\s*/i, '').trim().toLowerCase())
    .filter(w => w.length >= 1 && text.includes(w));
};
const albumPickPrompt = (db, topic, exclude, mood) =>
  '아래 사진 정보 목록의 각 사진이 앨범 조건에 맞는지 엄격하게 판정해 JSON만 출력하라.\n' +
  (topic ? '- 포함 조건: ' + topic + '\n' : '') +
  (mood ? '- 이 조건은 분위기다. 분위기를 만드는 단서 예: ' + mood.join(', ') + '\n' : '') +
  (exclude ? '- 제외 조건: ' + exclude + ' (해당하면 excluded=true)\n' : '') +
  '[판정 기준]\n' +
  (mood
    ? '- yes: 사진 정보(caption·background·weather·time·place 등)에 그 분위기를 만드는 시각 단서가 직접 적혀 있다. 단서가 없거나 다른 분위기(예: 밝고 신나는 장면에 "쓸쓸한")면 no. 짐작만 가능하면 maybe.\n' +
    '- 사진에 무엇이 찍혔는지가 아니라 사진 정보에 적힌 빛·색·날씨·시간·장면으로만 판단한다.\n'
    : '- yes: 조건의 구체적인 대상(또는 그 대상에 일반적으로 속하는 것)이 사진 정보에 직접 나온다. 넓은 범주만 같으면 no(예: 조건이 "패스트푸드"인데 파스타·케이크). 애매하면 maybe.\n') +
  '- evidence 에는 판정 근거가 된 낱말을 사진 정보에서 **글자 그대로** 복사해 배열로 적는다(최대 4개). 사진 정보에 없는 말은 쓰지 않는다.\n' +
  '사진 정보:' + JSON.stringify(db.map(pickView)) + '\n' +
  '{"checks":[{"id":사진 id,"verdict":"yes|maybe|no","evidence":["낱말"],"excluded":false}]}';
const PICK_BATCH = 25;
// 판정에 쓰인 사진 정보의 지문 — 다시 분석해 정보가 바뀌면 판정을 새로 받는다
const photoPrint = d => {
  const str = JSON.stringify(pickView(d));
  let h = 5381;
  for (let i = 0; i < str.length; i++) h = ((h * 33) ^ str.charCodeAt(i)) >>> 0;
  return h.toString(36);
};
const INFO_TYPES = new Set([...TEXT_DENSE, 'artwork']);

async function album(b) {
  const request = typeof b.request === 'string' ? b.request.trim().slice(0, 500) : '';
  if (!request || !Array.isArray(b.db) || b.db.length > 300) return [400, { error: 'bad_request' }];
  const db = b.db.map(slimPhoto);
  const cats = cleanCats(b.categories);
  // 1) 요청 → 조건. 앱이 같은 요청 문장으로 전에 받은 조건(plan)을 보내면 그대로 써서 매번 같은 결과가 나오게 한다
  // (AI 는 temperature 0 이어도 가끔 조건을 조금 다르게 뽑기 때문). 날짜가 바뀌면 '최근·작년' 해석이 달라지므로 다시 해석.
  const today = new Date().toISOString().slice(0, 10);
  const p = b.plan;
  const okQ = p && typeof p === 'object' && p.v === 1 && p.request === request &&
    p.q && typeof p.q === 'object' && !Array.isArray(p.q) && JSON.stringify(p.q).length <= 4000;
  const reuse = okQ && (p.today === today || !(p.q.time?.from || p.q.time?.to));
  const q = reuse ? p.q : await ask([{ type: 'input_text', text: albumParsePrompt(request, cats) }], { temperature: 0 });
  // seen: 이 요청으로 이미 판정한 사진 { id: [사진 정보 지문, 넣을지 1/0] } — 사진 정보가 그대로면 다시 묻지 않는다
  const prevSeen = reuse && p.seen && typeof p.seen === 'object' && !Array.isArray(p.seen) ? p.seen : {};
  const seen = {};
  const plan = { v: 1, request, today, q, seen };
  const title = String(q.title || '').trim().slice(0, 30) || request.slice(0, 15);
  const category = cats.some(c => c.id === q.category) ? q.category : null;

  // 2) 장소·시간은 서버가 정확히 거른다
  let cand = db;
  const terms = (q.place?.has && Array.isArray(q.place.terms) ? q.place.terms : [])
    .map(t => String(t).trim()).filter(t => t.length >= 2);
  if (terms.length) {
    // '성수동' ↔ '성수2가3동', '신촌동' ↔ '신촌동' 처럼 행정동 번호·'가'가 붙어도 맞도록 지명 줄기로도 비교
    const stems = [...new Set(terms.flatMap(t => {
      const stem = t.replace(/(\d*가)?\d*동$/, '');
      return stem.length >= 2 && stem !== t ? [t, stem] : [t];
    }))];
    const hit = d => stems.some(t => [d.addr, d.place, d.caption, d.summary].some(v => typeof v === 'string' && v.includes(t)));
    cand = cand.filter(hit);
    if (!cand.length) {
      const located = db.filter(d => d.addr).length;
      return [200, {
        title, ids: [], category, plan, reason: located
          ? `'${terms[0]}'에서 찍은 사진을 찾지 못했어요.`
          : '위치 정보가 있는 사진이 없어 장소로 찾을 수 없어요.'
      }];
    }
  }
  const from = /^\d{4}-\d{2}-\d{2}$/.test(q.time?.from || '') ? q.time.from : null;
  const to = /^\d{4}-\d{2}-\d{2}$/.test(q.time?.to || '') ? q.time.to : null;
  if (from || to) {
    cand = cand.filter(d => typeof d.date === 'string' && (!from || d.date >= from) && (!to || d.date <= to));
    if (!cand.length) return [200, { title, ids: [], category, plan, reason: '그 기간에 찍은 사진이 없어요.' }];
  }

  // 3) 주제·제외 조건은 남은 후보 중에서 AI 가 고른다
  const topic = typeof q.topic === 'string' && q.topic.trim() ? q.topic.trim().slice(0, 100) : null;
  const exclude = typeof q.exclude === 'string' && q.exclude.trim() ? q.exclude.trim().slice(0, 100) : null;
  const words = list => (Array.isArray(list) ? list : []).map(t => String(t).trim()).filter(Boolean).slice(0, 30);
  const moodCues = words(q.mood_cues);
  const mood = topic && q.kind === 'mood' && moodCues.length ? moodCues : null;
  // 분위기 앨범은 '사진'만 — 스크린샷·문서 같은 정보 이미지는 분위기 대상이 아니다
  if (mood) cand = cand.filter(d => !INFO_TYPES.has(String(d.type || '')));
  cand = [...cand].sort((x, y) => Number(x.id) - Number(y.id)); // 매번 같은 순서로 판정
  let ids = cand.map(d => Number(d.id));
  if (topic || exclude) {
    const topicTerms = mood ? [] : words(q.topic_terms); // 분위기는 낱말이 겹쳤다고 자동 포함하지 않음
    const excludeTerms = words(q.exclude_terms);
    // '먹은 것들'처럼 대상이 없는 넓은 요청일 때만 음식 사진 전체 (구체적인 이름 목록이 있으면 그 이름으로만)
    const broadFood = !mood && q.topic_broad === true && topicTerms.length === 0 && /음식|먹/.test(topic || '');
    // 사진 정보(음식·키워드·카테고리·캡션·요약·주제·장소)에 그 이름이 실제로 있으면 확실히 맞음
    const fields = d => [...(d.food || []), ...(d.kw || []), ...(d.cat || []), d.caption, d.summary, d.topic, d.place]
      .filter(v => typeof v === 'string').join(' ');
    const has = (d, list) => list.length > 0 && list.some(t => fields(d).includes(t));
    const sure = new Set(cand.filter(d => (broadFood && (d.food || []).length > 0) || has(d, topicTerms)).map(d => Number(d.id)));
    // AI 판정이 필요한 사진: 확실한 사진(제외 조건이 없을 때)은 빼고, 이 요청으로 이미 판정한 사진도 다시 묻지 않는다
    const need = d => !sure.has(Number(d.id)) || exclude;
    const memo = d => { const m = prevSeen[d.id]; return Array.isArray(m) && m[0] === photoPrint(d) ? m[1] === 1 : null; };
    const toCheck = cand.filter(d => need(d) && memo(d) === null);
    // 25장씩 나눠 판정 (프롬프트가 짧을수록 판정이 안정적)
    const batches = [];
    for (let i = 0; i < toCheck.length; i += PICK_BATCH) batches.push(toCheck.slice(i, i + PICK_BATCH));
    const results = await Promise.all(batches.map(part =>
      ask([{ type: 'input_text', text: albumPickPrompt(part, topic, exclude, mood) }], { temperature: 0 })));
    const checks = new Map(results.flatMap(r => (Array.isArray(r.checks) ? r.checks : [])).filter(Boolean).map(c => [Number(c.id), c]));
    // AI 기준으로 넣을지: 제외 조건에 안 걸리고, yes 이면서 그 근거 낱말이 실제 사진 정보에 있을 때만
    // (대충 관련된 사진·지어낸 근거는 제외)
    const aiKeep = d => {
      const known = memo(d);
      if (known !== null) return known;
      const id = Number(d.id), c = checks.get(id);
      if (c?.excluded === true) return false;
      if (sure.has(id) || !topic) return true; // 확실한 사진·주제 없는 요청은 제외 조건만 본다
      return c?.verdict === 'yes' && grounded(d, c.evidence).length > 0;
    };
    ids = cand.filter(d => {
      const id = Number(d.id);
      if (has(d, excludeTerms)) return false;
      if (exclude && /음식/.test(exclude) && (d.food || []).length > 0) return false;
      if (!need(d)) return true; // 확실한 사진
      const keep = aiKeep(d);
      if (checks.has(id) || memo(d) !== null) seen[id] = [photoPrint(d), keep ? 1 : 0];
      return keep;
    }).map(d => Number(d.id));
  }
  return [200, { title, ids, category, plan, reason: ids.length ? '' : '조건에 맞는 사진을 찾지 못했어요.' }];
}

// 사진 GPS 좌표 → 시·구·동 주소 (예: "서울특별시 성동구 성수2가3동")
// GOOGLE_MAPS_API_KEY 가 있으면 구글 지도, 없으면 OpenStreetMap(Nominatim, 키 불필요)을 쓴다.
const PLACE_TYPES = ['administrative_area_level_1', 'locality', 'sublocality_level_1', 'sublocality_level_2'];
async function googlePlace(lat, lng) {
  const url = 'https://maps.googleapis.com/maps/api/geocode/json?language=ko&latlng=' + lat.toFixed(6) + ',' + lng.toFixed(6) + '&key=' + encodeURIComponent(mapsKey());
  let r;
  try { r = await fetch(url, { signal: AbortSignal.timeout(10000) }); } catch (e) { throw fail(e.name === 'TimeoutError' ? 'timeout' : 'maps_unreachable'); }
  const j = await r.json().catch(() => ({}));
  if (j.status === 'ZERO_RESULTS') return null;
  if (j.status !== 'OK') { console.error('Google 지오코딩 오류', j.status, hide(j.error_message || '')); throw fail('maps_' + String(j.status || r.status).toLowerCase()); }
  const comps = j.results?.[0]?.address_components || [];
  const parts = [];
  for (const t of PLACE_TYPES) {
    const c = comps.find(c => c.types?.includes(t));
    if (c && !parts.includes(c.long_name)) parts.push(c.long_name);
  }
  return parts.join(' ') || String(j.results?.[0]?.formatted_address || '').replace(/^대한민국\s*/, '') || null;
}

// Nominatim 이용 정책: 초당 1회 이하 → 인스턴스 안에서 요청 간격을 1.1초 이상으로
let osmQueue = Promise.resolve();
const osmTurn = () => { const t = osmQueue.then(() => new Promise(ok => setTimeout(ok, 1100))); osmQueue = t; return osmQueue; };
const OSM_ORDER = [['province', 'state'], ['city'], ['county'], ['borough', 'city_district'], ['town', 'village'], ['quarter', 'suburb', 'neighbourhood']];
async function osmPlace(lat, lng) {
  const run = osmQueue;
  osmTurn();
  await run;
  const url = 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=16&addressdetails=1&accept-language=ko&lat=' + lat.toFixed(6) + '&lon=' + lng.toFixed(6);
  let r;
  try { r = await fetch(url, { headers: { 'User-Agent': 'Snapback/1.0' }, signal: AbortSignal.timeout(10000) }); } catch (e) { throw fail(e.name === 'TimeoutError' ? 'timeout' : 'maps_unreachable'); }
  if (!r.ok) { console.error('OSM 지오코딩 오류', r.status); throw fail('maps_' + r.status); }
  const a = (await r.json().catch(() => ({}))).address || {};
  const parts = [];
  for (const keys of OSM_ORDER) {
    const v = keys.map(k => a[k]).find(Boolean); // 같은 단계는 첫 값만 (법정동 quarter → 행정동 suburb)
    if (v && !parts.includes(v)) parts.push(v);
  }
  return parts.join(' ') || null;
}

async function place(b) {
  const lat = Number(b.lat), lng = Number(b.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return [400, { error: 'bad_request' }];
  const name = mapsKey() ? await googlePlace(lat, lng) : await osmPlace(lat, lng);
  return [200, { name, source: mapsKey() ? 'google' : 'osm' }];
}

// '기록으로 남기기' 초안: 사진(있으면) + 분석 정보 → 기록 종류·제목·추출 텍스트 등
const PLACE_KINDS = ['카페', '음식점', '여행지', '공원·자연', '전시·공연', '쇼핑', '기타'];
const RECORD =
  '너는 사진 기록 도우미다. 사진과 분석 정보를 보고 사용자가 남길 기록의 초안을 만들어라.\n' +
  '규칙:\n' +
  '- 사람의 이름·신원은 추측하지 마라.\n' +
  '- 문서 속 이름·생년월일·주민등록번호·주소·전화번호·계좌번호·카드번호 같은 개인 식별 정보는 절대 옮겨 적지 마라.\n' +
  '- type: 영수증·검진표·서류·표·화면 캡처처럼 글자가 중심이면 "document", 장소·음식·풍경이면 "place", 그 밖은 "moment".\n' +
  '- document 면 lines 에 핵심 항목을 "항목: 값" 형식으로 최대 12줄, summary 에 문서에 적힌 내용만 1~2문장으로 요약(진단·의학적 조언·추측 금지).\n' +
  '- 건강·의료, 금융, 신분증 정보가 있으면 sensitiveType 에 "건강정보"/"금융정보"/"신분정보", 없으면 null.\n' +
  '- place.kind 는 ' + JSON.stringify(PLACE_KINDS) + ' 중 하나.\n' +
  'JSON만 출력: {"type":"place|document|moment","title":"20자 이내 제목","date":"YYYY-MM-DD 또는 null","place":{"name":"장소 이름(모르면 \'동네 + 장소 유형\' 형태, 예: 성수동 카페)","kind":"장소 유형"},"lines":["..."],"summary":"...","sensitiveType":null}';

async function record(b) {
  const photo = b.photo && typeof b.photo === 'object' ? b.photo : null;
  if (!photo) return [400, { error: 'bad_request' }];
  const { thumb, e, ...info } = photo;
  const hint = typeof b.location === 'string' && b.location ? '\n촬영 위치(지도 기준): ' + b.location.slice(0, 80) : '';
  const content = [{ type: 'input_text', text: RECORD + '\n분석 정보:' + JSON.stringify(info).slice(0, 2000) + hint }];
  // 문서 글자를 읽어야 하므로 사진이 있으면 고해상도로 본다
  if (typeof b.image === 'string' && b.image.startsWith('data:image/')) content.push({ type: 'input_image', image_url: b.image, detail: 'high' });
  const r = await ask(content);
  const type = ['place', 'document', 'moment'].includes(r.type) ? r.type : 'moment';
  const str = (v, n) => (typeof v === 'string' ? v.trim().slice(0, n) : '');
  return [200, {
    type,
    title: str(r.title, 30),
    date: /^\d{4}-\d{2}-\d{2}$/.test(r.date || '') ? r.date : null,
    place: { name: str(r.place?.name, 40), kind: PLACE_KINDS.includes(r.place?.kind) ? r.place.kind : '기타' },
    lines: (Array.isArray(r.lines) ? r.lines : []).map(x => str(x, 80)).filter(Boolean).slice(0, 12),
    summary: str(r.summary, 200),
    sensitiveType: ['건강정보', '금융정보', '신분정보'].includes(r.sensitiveType) ? r.sensitiveType : null,
  }];
}

// '흩어진 순간 모으기' 제안: 사진 분석 DB를 보고 만들 만한 앨범 요청 문장 2~3개
const suggestPrompt = db =>
  '너는 스마트 갤러리의 앨범 큐레이터다. 아래 사진 DB를 보고, 사용자가 앨범으로 모으면 좋을 만한 주제를 골라 ' +
  '앨범 요청 문장 3개를 만들어라. 규칙: 실제로 DB에 사진이 여러 장 있는 주제만, 서로 겹치지 않게, ' +
  '각 문장은 22자 이내의 자연스러운 한국어(예: "올여름 친구들과 함께했던 순간들", "비 오는 날 카페 사진만 모아줘"), ' +
  '사람 이름·신원은 쓰지 마라.\nDB:' + JSON.stringify(db) +
  '\nJSON만 출력: {"suggestions":["문장1","문장2","문장3"]}';

async function suggest(b) {
  if (!Array.isArray(b.db) || b.db.length > 300) return [400, { error: 'bad_request' }];
  if (b.db.length === 0) return [200, { suggestions: [] }];
  const db = b.db.map(slimPhoto);
  const r = await ask([{ type: 'input_text', text: suggestPrompt(db) }]);
  const suggestions = [...new Set((Array.isArray(r.suggestions) ? r.suggestions : [])
    .map(x => String(x || '').trim().slice(0, 30)).filter(Boolean))].slice(0, 3);
  return [200, { suggestions }];
}

// 기억 키워드가 사진 정보와 확실히 어긋나는지 (계절 ↔ 촬영 월, 날씨, 시간대). 사용자의 기억이 틀렸을 수 있다.
const SEASONS = { 봄: [3, 4, 5], 여름: [6, 7, 8], 가을: [9, 10, 11], 겨울: [12, 1, 2] };
const WEATHER_GROUPS = [['맑음', '맑은', '맑았', '화창', '햇살'], ['비', '비오는', '비 오는', '우산', '장마'], ['눈', '눈오는', '눈 오는', '함박눈'], ['흐림', '흐린', '흐렸']];
const TIME_GROUPS = [['아침', '새벽', '오전'], ['낮', '점심', '오후'], ['저녁', '노을', '해질녘'], ['밤', '야경', '새벽녘']];
function conflictsWithPhoto(word, photo) {
  const w = String(word).trim();
  const month = /^\d{4}-(\d{2})/.exec(String(photo.date || ''))?.[1];
  if (SEASONS[w] && month && !SEASONS[w].includes(Number(month))) return true;
  const group = (groups, v) => groups.findIndex(g => g.some(x => String(v || '').includes(x)));
  const wg = WEATHER_GROUPS.findIndex(g => g.includes(w));
  if (wg >= 0 && photo.weather && group(WEATHER_GROUPS, photo.weather) >= 0 && group(WEATHER_GROUPS, photo.weather) !== wg) return true;
  const tg = TIME_GROUPS.findIndex(g => g.includes(w));
  if (tg >= 0 && photo.time && group(TIME_GROUPS, photo.time) >= 0 && group(TIME_GROUPS, photo.time) !== tg) return true;
  return false;
}

// 키워드로 쓸모없는 일반 낱말·동사
const GENERIC_RECALL = new Set(['사진', '날', '그날', '때', '그때', '것', '거', '곳', '먹은', '먹던', '먹었던', '마신', '마셨던', '간', '갔던', '가서', '찍은', '찍었던', '본', '봤던', '한', '했던', '놀던', '만난', '있던', '같은', '어떤', '뭔가', '무슨']);

// '맞아요'로 찾은 사진에 붙일 키워드: 기억 문장·질문 답에서, 사진 정보에 아직 없는 새 정보만 뽑는다
const recallPrompt = (photo, query, answers) =>
  '사용자가 아래 기억 문장(과 질문 답)으로 갤러리에서 이 사진을 찾았고 "맞아요"로 확인했다. ' +
  '다음에 같은 사진을 더 잘 찾도록, 이 사진에 붙일 검색 키워드를 뽑아 JSON만 출력하라.\n' +
  '[규칙]\n' +
  '- 기억 문장·답에 실제로 나온 낱말만. 사진 정보에서 가져오거나 지어내지 않는다.\n' +
  '- 사용자의 기억이 틀렸을 수 있다. 사진 정보와 어긋나는 내용(예: 문장은 "여름"인데 date 가 12월, "바다"인데 place 가 카페, "비"인데 weather 가 맑음, 다른 음식)은 넣지 않는다.\n' +
  '- 조사·어미를 뗀 기본형 낱말(명사 위주, 예: "카페에서"→"카페", "친구랑"→"친구", "먹은"→ 빼거나 "먹기").\n' +
  '- 사진 정보에 이미 같은 낱말이 있으면 빼고, 사진 정보가 놓친 새 정보(누구와, 상황, 행사, 감정, 이름 붙은 장소 등)를 우선한다.\n' +
  '- "사진, 날, 그때, 거, 것, 때" 같은 일반 낱말과 사람 이름·전화번호 같은 개인 식별 정보는 넣지 않는다.\n' +
  '- 3~8개, 각 10자 이내.\n' +
  '- 각 낱말의 conflict: 사진 정보의 같은 항목에 **다른 값이 분명히 적혀 있을 때만** "yes"(예: "바닷가" ↔ place 카페, "빙수" ↔ food 케이크만, "여름" ↔ date 12월). ' +
  '사진 정보에 그 항목이 없거나 판단할 수 없으면 "unknown"(예: 함께 간 사람, 행사, 감정, 동네 이름은 대개 unknown). 맞으면 "no".\n' +
  '사진 정보:' + JSON.stringify(photo) + '\n기억 문장:' + JSON.stringify(query) +
  (answers.length ? '\n질문 답:' + JSON.stringify(answers) : '') +
  '\n{"keywords":[{"word":"낱말","conflict":"no|unknown|yes"}]}';
async function recall(b) {
  const query = typeof b.query === 'string' ? b.query.trim().slice(0, 300) : '';
  if (!query || !b.photo || typeof b.photo !== 'object' || Array.isArray(b.photo)) return [400, { error: 'bad_request' }];
  const answers = (Array.isArray(b.answers) ? b.answers : []).map(a => String(a).trim().slice(0, 80)).filter(Boolean).slice(0, 6);
  const photo = slimPhoto({ ...b.photo });
  const r = await ask([{ type: 'input_text', text: recallPrompt(photo, query, answers) }], { temperature: 0 });
  // 사용자가 실제로 말한 낱말만(문장·답에 그대로 있는 것), 사진 정보에 이미 있는 낱말·사진과 어긋나는 낱말은 제외
  const said = (query + ' ' + answers.join(' ')).toLowerCase();
  const known = photoWords(photo);
  const keywords = [...new Set((Array.isArray(r.keywords) ? r.keywords : [])
    .filter(k => !(k && typeof k === 'object' && (k.conflict === 'yes' || k.conflict === true)))
    .map(k => scrubPII(String((k && typeof k === 'object' ? k.word : k) || '').trim()).slice(0, 15))
    .filter(k => !conflictsWithPhoto(k, photo) && !GENERIC_RECALL.has(k))
    .filter(k => k && !/단서|낱말/.test(k) && said.includes(k.toLowerCase()) && !known.includes(k.toLowerCase())))].slice(0, 8);
  return [200, { keywords }];
}

const POST_ROUTES = { analyze, search, album, place, record, suggest, recall };

// route: 'health' | 'analyze' | 'search' | 'album' | 'place' | 'record' | 'suggest' | 'recall' (그 외는 404)
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
    try { send(res, c === 'too_big' ? 413 : c === 'bad_request' ? 400 : e.code ? 502 : 500, { error: c }); } catch { }
  }
}
