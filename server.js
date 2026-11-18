// 기억(Memory) — 최소 백엔드: 브라우저 → 이 서버 → OpenAI API. API 키는 서버에만 둔다.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const KEY = process.env.OPENAI_API_KEY;
const MODEL = process.env.OPENAI_MODEL || 'gpt-4o-mini';
const PORT = process.env.PORT || 3000;
const PUB = path.join(path.dirname(fileURLToPath(import.meta.url)), 'public');
if (!KEY) { console.error('OPENAI_API_KEY 가 없어요. .env 파일을 확인하세요.'); process.exit(1); }
// 키 모양만 확인 (키 내용은 절대 출력하지 않음)
const KEY_OK = /^sk-[\w-]{20,}$/.test(KEY);
if (!KEY_OK) console.warn('⚠️  .env 의 OPENAI_API_KEY 가 예시 문구 그대로이거나 형식이 이상해요. 실제 키로 바꾼 뒤 서버를 다시 시작하세요.');
const fail = c => Object.assign(new Error(c), { code: c });          // 브라우저로 보낼 오류 코드
const hide = s => String(s).replace(/sk-[\w\-*.]+/g, 'sk-***');     // 로그에 키가 섞여도 가림

// OpenAI Responses API 호출 → JSON 객체로 반환
async function ask(content) {
  let r;
  try {
    r = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + KEY },
      body: JSON.stringify({ model: MODEL, input: [{ role: 'user', content }], text: { format: { type: 'json_object' } } }),
      signal: AbortSignal.timeout(60000), // 60초 넘으면 중단
    });
  } catch (e) { throw fail(e.name === 'TimeoutError' ? 'timeout' : 'openai_unreachable'); }
  if (!r.ok) { console.error('OpenAI 오류', r.status, hide((await r.text()).slice(0, 300))); throw fail('openai_' + r.status); }
  const j = await r.json();
  const text = (j.output || []).flatMap(o => o.content || []).map(c => c.text || '').join('');
  try { return JSON.parse(text); } catch { console.error('AI 응답이 JSON이 아님:', hide(text.slice(0, 200))); throw fail('bad_ai_json'); }
}

// 프롬프트는 서버가 소유 (프론트에서 마음대로 못 바꿈)
const ANALYZE = '이 사진을 분석해 JSON만 출력(이름·신원 추측 금지): {"caption":"한 문장","food":["음식"],"place":"장소 유형","people":"인원수·옷차림 등 특성","background":"배경","weather":"날씨","time":"낮/저녁/밤/알 수 없음"}';
const searchPrompt = (db, hist) =>
  '너는 스마트 갤러리 기억 검색 엔진이다. 사진 DB에서 사용자의 흐릿한 기억과 대화 기록에 가장 맞는 사진을 찾아라.\nDB:' + JSON.stringify(db) +
  '\n대화:' + JSON.stringify(hist) +
  '\nJSON만 출력: {"ranked":[{"id":숫자,"score":0-100,"matched":["맞은 단서"],"missing":["확인 안 된 단서"]}],"question":{"text":"후보를 가장 잘 가르는 질문 하나","options":["선택지 2~3개"]} 또는 null(후보가 뚜렷하면)}';

const hits = new Map(); // IP당 분당 30회 제한
const limited = ip => { const n = Date.now(), a = (hits.get(ip) || []).filter(t => n - t < 60000); a.push(n); hits.set(ip, a); return a.length > 30; };
const body = req => new Promise((ok, no) => { let b = ''; req.on('data', c => { b += c; if (b.length > 6e6) { no(new Error('too big')); req.destroy(); } }); req.on('end', () => { try { ok(JSON.parse(b || '{}')); } catch (e) { no(e); } }); });
const send = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png' };

http.createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && req.url === '/api/health') return send(res, 200, { ok: true, key: KEY_OK, model: MODEL });
    if (req.method === 'POST' && req.url.startsWith('/api/')) {
      if (limited(req.socket.remoteAddress)) return send(res, 429, { error: 'rate_limited' });
      const b = await body(req);
      if (req.url === '/api/analyze') {
        if (typeof b.image !== 'string' || !b.image.startsWith('data:image/')) return send(res, 400, { error: 'bad_image' });
        return send(res, 200, await ask([{ type: 'input_text', text: ANALYZE }, { type: 'input_image', image_url: b.image }]));
      }
      if (req.url === '/api/search') {
        if (!Array.isArray(b.db) || !Array.isArray(b.hist) || b.db.length > 300) return send(res, 400, { error: 'bad_request' });
        const db = b.db.map(({ thumb, e, ...d }) => d); // 썸네일은 모델에 보내지 않음
        return send(res, 200, await ask([{ type: 'input_text', text: searchPrompt(db, b.hist.slice(-12)) }]));
      }
      return send(res, 404, { error: 'not_found' });
    }
    const f = path.join(PUB, req.url === '/' ? 'index.html' : path.normalize(req.url.split('?')[0]).replace(/^(\.\.[/\\])+/, ''));
    if (!f.startsWith(PUB) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
    fs.createReadStream(f).pipe(res);
  } catch (e) {
    const c = e.code || (e.message === 'too big' ? 'too_big' : e instanceof SyntaxError ? 'bad_request' : 'server_error');
    console.error('요청 실패:', c, hide(e.message));
    try { send(res, c === 'too_big' ? 413 : c === 'bad_request' ? 400 : e.code ? 502 : 500, { error: c }); } catch {}
  }
}).listen(PORT, () => console.log('http://localhost:' + PORT));
