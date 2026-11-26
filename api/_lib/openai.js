// OpenAI 호출: Chat Completions(JSON) · Embeddings(256차원)
import { MODEL, key, fail, hide } from './config.js';

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

// ── 임베딩 (하이브리드 검색 1차 선별용) ──────────────────────────
// 사진 설명·검색어를 256차원 벡터로. 벡터는 앱이 기기에만 저장하고, 검색 때는 검색어 한 문장만 벡터로 바꿔
// 기기 안에서 코사인 유사도로 후보를 고른다 (서버는 아무것도 저장하지 않음).
const EMBED_MODEL = 'text-embedding-3-small';
const EMBED_DIM = 256;
const EMBED_MAX_TEXTS = 50;
const EMBED_MAX_CHARS = 2000;
async function embedTexts(texts) {
  if (!key()) throw fail('no_api_key');
  let r;
  try {
    r = await fetch('https://api.openai.com/v1/embeddings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + key() },
      body: JSON.stringify({ model: EMBED_MODEL, input: texts, dimensions: EMBED_DIM }),
      signal: AbortSignal.timeout(30000),
    });
  } catch (e) { throw fail(e.name === 'TimeoutError' ? 'timeout' : 'openai_unreachable'); }
  if (!r.ok) { console.error('OpenAI 임베딩 오류', r.status, hide((await r.text()).slice(0, 300))); throw fail('openai_' + r.status); }
  const j = await r.json();
  const out = new Array(texts.length).fill(null);
  for (const d of Array.isArray(j.data) ? j.data : []) {
    const v = d?.embedding;
    if (Number.isInteger(d?.index) && d.index < texts.length && Array.isArray(v) && v.length === EMBED_DIM) {
      out[d.index] = v.map(x => Math.round(x * 1e5) / 1e5); // 응답 크기를 줄이려고 소수 5자리
    }
  }
  return out;
}

export { toChat, ask, EMBED_MODEL, EMBED_DIM, EMBED_MAX_TEXTS, EMBED_MAX_CHARS, embedTexts };
