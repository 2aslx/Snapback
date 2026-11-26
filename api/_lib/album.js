// 자연어 앨범 (/api/album) · 앨범 제안 (/api/suggest)
import { ask } from './openai.js';
import { TEXT_DENSE } from './analyze.js';
import { slimPhoto, MAX_DB, AI_DB, lexWords, narrowDb } from './photos.js';

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
const PICK_FIELDS = ['caption', 'background', 'weather', 'time', 'place', 'food', 'people', 'cat', 'topic', 'summary', 'kw', 'type', 'items', 'text'];
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
  '- evidence 에는 판정 근거가 된 낱말을 사진 정보에서 **글자 그대로** 복사해 배열로 적는다(최대 3개). 사진 정보에 없는 말은 쓰지 않는다.\n' +
  '- 응답을 짧게: matches 에는 yes·maybe 인 사진만 넣고 no 인 사진은 넣지 않는다. 제외 조건에 해당하는 사진은 excluded 에 id 만 적는다.\n' +
  '사진 정보:' + JSON.stringify(db.map(pickView)) + '\n' +
  '{"matches":[{"id":사진 id,"verdict":"yes|maybe","evidence":["낱말"]}],"excluded":[사진 id]}';
const PICK_BATCH = 50;
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
  if (!request || !Array.isArray(b.db) || b.db.length > MAX_DB) return [400, { error: 'bad_request' }];
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
    const fields = d => [...(d.food || []), ...(d.kw || []), ...(d.cat || []), d.caption, d.summary, d.topic, d.place, d.items, d.text]
      .filter(v => typeof v === 'string').join(' ');
    const has = (d, list) => list.length > 0 && list.some(t => fields(d).includes(t));
    const sure = new Set(cand.filter(d => (broadFood && (d.food || []).length > 0) || has(d, topicTerms)).map(d => Number(d.id)));
    // AI 판정이 필요한 사진: 확실한 사진(제외 조건이 없을 때)은 빼고, 이 요청으로 이미 판정한 사진도 다시 묻지 않는다
    const need = d => !sure.has(Number(d.id)) || exclude;
    const memo = d => { const m = prevSeen[d.id]; return Array.isArray(m) && m[0] === photoPrint(d) ? m[1] === 1 : null; };
    // 판정할 사진이 300장을 넘으면 주제 낱말이 많이 겹치는 300장만 AI 가 판정 (나머지는 확실한 사진이 아니면 제외,
    // 주제 없이 제외 조건만 있는 요청이면 규칙으로만 거르고 유지)
    const toCheck = narrowDb(cand.filter(d => need(d) && memo(d) === null),
      lexWords([topic, ...words(q.topic_terms), ...moodCues, request]));
    // 50장씩 나눠 판정 (맞는 사진만 답하게 해서 응답이 짧다)
    const batches = [];
    for (let i = 0; i < toCheck.length; i += PICK_BATCH) batches.push(toCheck.slice(i, i + PICK_BATCH));
    const results = await Promise.all(batches.map(part =>
      ask([{ type: 'input_text', text: albumPickPrompt(part, topic, exclude, mood) }], { temperature: 0 })));
    // 판정한 사진마다 { verdict, evidence, excluded } — 답에 없는 사진은 no
    const checks = new Map(toCheck.map(d => [Number(d.id), { verdict: 'no', evidence: [], excluded: false }]));
    for (const r of results) {
      for (const m of Array.isArray(r.matches) ? r.matches : []) {
        const c = m && checks.get(Number(m.id));
        if (c) Object.assign(c, { verdict: m.verdict === 'yes' ? 'yes' : 'maybe', evidence: Array.isArray(m.evidence) ? m.evidence : [] });
      }
      for (const id of Array.isArray(r.excluded) ? r.excluded : []) {
        const c = checks.get(Number(id));
        if (c) c.excluded = true;
      }
    }
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

// '흩어진 순간 모으기' 제안: 사진 분석 DB를 보고 만들 만한 앨범 요청 문장 2~3개
const suggestPrompt = db =>
  '너는 스마트 갤러리의 앨범 큐레이터다. 아래 사진 DB를 보고, 사용자가 앨범으로 모으면 좋을 만한 주제를 골라 ' +
  '앨범 요청 문장 3개를 만들어라. 규칙: 실제로 DB에 사진이 여러 장 있는 주제만, 서로 겹치지 않게, ' +
  '각 문장은 22자 이내의 자연스러운 한국어(예: "올여름 친구들과 함께했던 순간들", "비 오는 날 카페 사진만 모아줘"), ' +
  '사람 이름·신원은 쓰지 마라.\nDB:' + JSON.stringify(db) +
  '\nJSON만 출력: {"suggestions":["문장1","문장2","문장3"]}';

async function suggest(b) {
  if (!Array.isArray(b.db) || b.db.length > MAX_DB) return [400, { error: 'bad_request' }];
  if (b.db.length === 0) return [200, { suggestions: [] }];
  // 사진이 많으면 최근 300장으로 제안
  const db = [...b.db].sort((x, y) => String(y.date || '').localeCompare(String(x.date || ''))).slice(0, AI_DB).map(slimPhoto);
  const r = await ask([{ type: 'input_text', text: suggestPrompt(db) }]);
  const suggestions = [...new Set((Array.isArray(r.suggestions) ? r.suggestions : [])
    .map(x => String(x || '').trim().slice(0, 30)).filter(Boolean))].slice(0, 3);
  return [200, { suggestions }];
}

export { DEFAULT_CATS, cleanCats, albumParsePrompt, PICK_FIELDS, pickView, pickText, grounded, albumPickPrompt, PICK_BATCH, photoPrint, INFO_TYPES, album, suggestPrompt, suggest };
