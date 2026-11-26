// 기억 검색 (/api/search): 순위 정리 · 질문 중복 막기
import { ask } from './openai.js';
import { slimPhoto, normQ, photoWords, MAX_DB, lexWords, narrowDb } from './photos.js';

const searchPrompt = (db, hist, extra = '') =>
  '너는 스마트 갤러리 기억 검색 엔진이다. 사진 DB에서 사용자의 흐릿한 기억과 대화 기록에 가장 맞는 사진을 찾아라. ' +
  'rk 는 사용자가 예전에 이 사진을 직접 찾아 "맞아요"로 확인한 키워드, rq 는 그때 쓴 기억 문장이다(사용자가 확인한 사실이므로 강한 단서로 본다). ' +
  'items 는 이미지에서 추출한 제품명·목록·시험명·항목 등 구조화 정보, text 는 이미지 속 글자, addr 는 촬영 위치의 시·구·동 주소다. 신촌·홍대 같은 생활권 지명은 해당 행정 주소와 연결해 판단하라.\nDB:' + JSON.stringify(db) +
  '\n대화:' + JSON.stringify(hist) +
  '\n규칙: 대화에 이미 나온 질문과 같거나 비슷한 주제(건너뛴 질문 포함)는 절대 다시 묻지 마라. 더 이상 가를 새 질문이 없거나 후보가 뚜렷하면 question을 null로 반환하라.' +
  (extra ? '\n' + extra : '') +
  '\n대화의 "Q: … / A: …" 에서 A 는 사용자가 확인해 준 사실이다. 답과 맞는 사진은 점수를 크게 올리고, 답과 어긋나는 사진(예: 답이 "비"인데 weather 가 흐림·맑음)은 크게 낮춰라. 답이 "모르겠어요"·건너뛰기면 무시하라.' +
  '\nranked 에는 기억과 관련 있는 사진(점수 40 이상)만 점수 높은 순으로 최대 30개 넣어라. 응답을 짧게: matched·missing 은 각각 최대 3개의 짧은 낱말.' +
  '\nmatched 에는 기억과 맞은 단서를 그 사진 정보에서 **글자 그대로** 복사한 낱말로 적어라(사진 정보에 없는 말은 쓰지 마라).' +
  '\nJSON만 출력: {"ranked":[{"id":숫자,"score":0-100,"matched":["맞은 단서"],"missing":["확인 안 된 단서"]}],"question":{"text":"아직 묻지 않은, 후보를 가장 잘 가르는 질문 하나","options":["선택지 2~3개"]} 또는 null}';

const askedQuestions = hist => hist.map(h => String(h).match(/^Q:\s*(.+?)\s*\/\s*A:/)?.[1]).filter(Boolean);
const isDupQ = (q, asked) => {
  const n = normQ(q?.text);
  return !n || asked.some(a => normQ(a) === n);
};

// wantQuestion: 사용자가 '질문 한 번 더하기'를 눌렀을 때 — 질문 개수 제한 없이 반드시 하나 만들도록 요청
const WANT_Q = '사용자가 추가 질문을 요청했다. 현재 상위 후보들을 가장 잘 구분하는 새 질문을 반드시 하나 만들어라(question을 null로 두지 마라).';

// 검색 순위를 서버가 일정하게 정한다: AI 점수를 5점 단위로 묶고 → 실제 사진 정보에 있는 단서가 많은 순 → 사진 id 순.
// AI 가 댄 단서 중 그 사진 정보에 없는 것(지어낸 근거)은 하나당 10점 감점, 하나도 없으면 40점 이하로 내린다.
// 사용자가 질문에 답한 낱말이 사진 정보에 있는 사진을 먼저 세운다 (AI 가 답을 놓쳐도 답과 맞는 사진이 위로).
const SEARCH_TOP = 30;  // 앱에 보내는 순위 (앱이 일치도 60~85% 후보를 모두 보여 줌)
const SEARCH_POOL = 30; // 답한 뒤 다시 찾을 후보 범위 (pool)
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
  if (!Array.isArray(b.db) || !Array.isArray(b.hist) || b.db.length > MAX_DB) return [400, { error: 'bad_request' }];
  const hist = b.hist.slice(-12);
  // 썸네일·구조화 정보는 모델에 보내지 않음. 300장이 넘으면 기억 문장·답과 낱말이 많이 겹치는 300장만
  const said = [hist[0], ...hist.slice(1).map(h => String(h).match(/\/\s*A:\s*(.+)$/)?.[1])];
  const db = narrowDb(b.db.map(slimPhoto), lexWords(said));
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

export { searchPrompt, askedQuestions, isDupQ, WANT_Q, SEARCH_TOP, SEARCH_POOL, VAGUE_ANSWER, answerWords, rankStable, search };
