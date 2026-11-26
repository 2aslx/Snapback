// 검색·앨범·제안 요청용 사진 정보 다듬기 · 사진이 많을 때 300장 고르기

// 검색·앨범·제안 요청용 사진 정보: 썸네일·원본 구조화 맵은 빼되 평탄화한 items 와 글자(text)는 포함
const slimPhoto = ({ thumb, e, data, ...d }) => {
  if (typeof d.text === 'string' && d.text.length > 240) d.text = d.text.slice(0, 240);
  if (typeof d.items === 'string' && d.items.length > 260) d.items = d.items.slice(0, 260);
  if (typeof d.summary === 'string' && d.summary.length > 160) d.summary = d.summary.slice(0, 160);
  if (Array.isArray(d.kw)) d.kw = d.kw.slice(0, 10);
  return d;
};

const normQ = s => String(s || '').replace(/[\s?!.,'"`~]/g, '').toLowerCase();
const photoWords = d => Object.entries(d).filter(([k]) => k !== 'id')
  .flatMap(([, v]) => (Array.isArray(v) ? v : [v])).filter(v => typeof v === 'string').join(' ').toLowerCase();
// 사진이 많을 때: 서버는 최대 MAX_DB 장까지 받고, AI 에는 AI_DB 장까지만 보낸다.
// 넘치면 기억 문장·답·요청의 낱말이 사진 정보에 많이 나오는 사진부터 고른다 (AI 호출 없이, 매번 같은 결과).
const MAX_DB = 2000;
const AI_DB = 300;
const JOSA = /(에서|에게|으로|이랑|하고|까지|부터|처럼|이나|에|로|을|를|이|가|은|는|와|과|랑|의|도|만)$/;
const STOP_WORDS = new Set(['그', '날', '때', '것', '거', '좀', '사진', '그때', '그날', '있던', '했던', '먹은', '찍은', '같은', '모아줘', '보여줘', '찾아줘']);
const lexWords = texts => {
  const out = new Set();
  for (const t of texts) {
    for (const w of String(t || '').toLowerCase().split(/[\s,.!?~"'()/:·→]+/)) {
      for (const v of [w, w.replace(JOSA, '')]) if (v && !STOP_WORDS.has(v) && (v.length >= 2 || /^[가-힣]$/.test(v))) out.add(v);
    }
  }
  return [...out];
};
function narrowDb(db, words, n = AI_DB) {
  if (db.length <= n) return db;
  const score = d => { const t = photoWords(d); return words.filter(w => t.includes(w)).length; };
  return db.map(d => [d, score(d)])
    .sort((x, y) => y[1] - x[1] || String(y[0].date || '').localeCompare(String(x[0].date || '')) || Number(x[0].id) - Number(y[0].id))
    .slice(0, n).map(x => x[0]);
}

export { slimPhoto, normQ, photoWords, MAX_DB, AI_DB, JOSA, STOP_WORDS, lexWords, narrowDb };
