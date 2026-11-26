// 공용 API 로직: 로컬 server.js 와 Vercel 함수(api/*.js)가 함께 사용한다.
// '_' 로 시작하는 파일은 Vercel 이 함수로 배포하지 않는다.
// API 키는 서버(환경변수)에만 있고 브라우저/앱으로는 절대 내려가지 않는다.
// 기능별 로직은 api/_lib/*.js 에 있다 ('_' 로 시작하는 폴더도 Vercel 이 함수로 배포하지 않음). 이 파일은 요청 처리만.
import { MODEL, keyOk, hide, mapsKey } from './_lib/config.js';
import { EMBED_DIM, embedTexts } from './_lib/openai.js';
import { capJson, scrubPII, piiValues, scrubData } from './_lib/pii.js';
import { normalizeAnalysis, analyze, analysisEmbedText, embed } from './_lib/analyze.js';
import { slimPhoto, MAX_DB, AI_DB, lexWords, narrowDb } from './_lib/photos.js';
import { askedQuestions, isDupQ, answerWords, rankStable, search } from './_lib/search.js';
import { cleanCats, grounded, PICK_BATCH, photoPrint, album, suggest } from './_lib/album.js';
import { place } from './_lib/place.js';
import { record } from './_lib/record.js';
import { conflictsWithPhoto, recall } from './_lib/recall.js';

export { keyOk } from './_lib/config.js';

// IP당 분당 요청 제한 (서버리스에서는 인스턴스별로 집계됨)
// 사진 분석은 앱이 여러 장을 동시에 보내므로 120회, 임베딩은 기존 사진 채우기(50장씩)·검색어용이라 60회, 나머지(검색·앨범 등)는 30회
const LIMITS = { analyze: 120, embed: 60 };
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

const POST_ROUTES = { analyze, search, album, place, record, suggest, recall, embed };

// route: 'health' | 'analyze' | 'search' | 'album' | 'place' | 'record' | 'suggest' | 'recall' | 'embed' (그 외는 404)
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

// 단위 테스트용 (test/core.test.mjs). 서버 동작에는 쓰지 않는다.
export const __test = {
  scrubPII, scrubData, piiValues, normalizeAnalysis, capJson, slimPhoto,
  rankStable, answerWords, isDupQ, askedQuestions, cleanCats,
  grounded, photoPrint, conflictsWithPhoto,
  analyze, search, album, recall, suggest,
  lexWords, narrowDb, MAX_DB, AI_DB, PICK_BATCH,
  embed, embedTexts, analysisEmbedText, EMBED_DIM,
};
