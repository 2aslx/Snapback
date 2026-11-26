// 서버 로직(api/_core.js) 단위 테스트 — `npm test`
// OpenAI 는 실제로 부르지 않는다: fetch 를 가짜로 바꿔 미리 정한 AI 응답을 돌려준다 (키·비용·네트워크 불필요).
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { Readable } from 'node:stream';

process.env.OPENAI_API_KEY = 'sk-test-' + 'x'.repeat(24);
const { __test: T, handleApi } = await import('../api/_core.js');

// ── 가짜 OpenAI ─────────────────────────────────────────────
let replies = [];
let calls = [];
let embedCalls = [];
let embedFail = false;
// 글자에서 결정적으로 만든 256차원 가짜 임베딩
const fakeVec = t => Array.from({ length: 256 }, (_, i) => ((String(t).charCodeAt(i % String(t).length) || 1) % 17) / 17);
globalThis.fetch = async (url, opts) => {
  assert.match(String(url), /api\.openai\.com/, 'OpenAI 말고 다른 곳을 부르면 안 됨');
  const body = JSON.parse(opts.body);
  if (String(url).endsWith('/embeddings')) {
    embedCalls.push(body);
    if (embedFail) return { ok: false, status: 500, json: async () => ({}), text: async () => 'fail' };
    const data = body.input.map((t, index) => ({ index, embedding: fakeVec(t) }));
    return { ok: true, status: 200, json: async () => ({ data }), text: async () => '' };
  }
  calls.push(body);
  assert.ok(replies.length, 'AI 응답이 더 필요함 (예상보다 많이 호출됨)');
  const reply = replies.shift();
  const text = JSON.stringify({ choices: [{ message: { content: JSON.stringify(reply) } }] });
  return { ok: true, status: 200, json: async () => JSON.parse(text), text: async () => text };
};
const aiReplies = (...r) => { replies = r; calls = []; };
beforeEach(() => { replies = []; calls = []; embedCalls = []; embedFail = false; });

// ── 개인정보 제거 ───────────────────────────────────────────
test('scrubPII: 전화·주민번호·이메일·계좌·라벨 붙은 값 제거', () => {
  const out = T.scrubPII('연락처: 010-1234-5678 주민 900101-1234567 메일 a.b@test.com 계좌 110-123-456789 성명: 홍길동 영수증');
  for (const bad of ['010-1234-5678', '900101-1234567', 'a.b@test.com', '110-123-456789', '홍길동']) {
    assert.ok(!out.includes(bad), `${bad} 가 남아 있음: ${out}`);
  }
  assert.ok(out.includes('영수증'));
});

test('scrubData: 개인정보 키 제거, 최상위 이름만 개인정보로 보고 목록 속 제품 이름은 유지', () => {
  const out = T.scrubData({ 이름: '김테스트', 전화번호: '010-1111-2222', 추천제품: [{ name: '보습 크림', 가격: '12,000원' }] });
  assert.equal(out.이름, undefined);
  assert.equal(out.전화번호, undefined);
  assert.deepEqual(out.추천제품, [{ name: '보습 크림', 가격: '12,000원' }]);
});

test('normalizeAnalysis: 성명 값을 캡션·요약에서도 지우고, 형식·길이·유형을 정리', () => {
  const r = T.normalizeAnalysis({
    image_type: 'Certificate!!',
    caption: '김테스트의 토익 성적표, 문의 010-9999-8888',
    content_summary: '김테스트 응시자의 시험 결과',
    structured_data: { 성명: '김테스트', 시험명: 'TOEIC', 점수: 900 },
    place: '사무실',
    time: '한밤중',
    suggested_record_type: 'unknown',
    search_keywords: 'toeic',
  });
  assert.equal(r.analysis_version, 2);
  assert.equal(r.image_type, 'certificate');
  assert.equal(r.text_dense, true);
  assert.ok(!r.caption.includes('김테스트') && !r.caption.includes('010-9999-8888'), r.caption);
  assert.ok(!r.content_summary.includes('김테스트'), r.content_summary);
  assert.deepEqual(r.structured_data, { 시험명: 'TOEIC', 점수: 900 });
  assert.equal(r.place, '', '문서 이미지는 촬영 장소가 없음');
  assert.equal(r.time, '', '정해진 시간대 값만 허용');
  assert.equal(r.suggested_record_type, 'moment');
  assert.deepEqual(r.search_keywords, ['toeic']);
});

test('normalizeAnalysis: 플랫폼을 장소로 적으면 비우고, 일반 사진 장소는 유지', () => {
  assert.equal(T.normalizeAnalysis({ image_type: 'photo', place: '인스타그램 화면' }).place, '');
  assert.equal(T.normalizeAnalysis({ image_type: 'photo', place: '카페', time: '저녁' }).place, '카페');
});

test('capJson: 정해진 길이 안으로 줄임', () => {
  const big = { list: Array.from({ length: 50 }, (_, i) => ({ item: 'x'.repeat(100) + i })) };
  assert.ok(JSON.stringify(T.capJson(big, 1500)).length <= 1500);
});

test('slimPhoto: 썸네일·원본 구조화 정보 제거', () => {
  const s = T.slimPhoto({ id: 1, thumb: 'data:...', e: '🖼️', data: { a: 1 }, caption: 'x', kw: Array(20).fill('k') });
  assert.equal(s.thumb, undefined);
  assert.equal(s.data, undefined);
  assert.ok(s.kw.length <= 10);
});

// ── 검색 순위 ─────────────────────────────────────────────
test('rankStable: 없는 사진·중복 제거, 지어낸 단서 감점, 점수→단서 수→id 순', () => {
  const db = [
    { id: 1, caption: '카페 라떼', weather: '비' },
    { id: 2, caption: '카페 케이크', weather: '맑음' },
    { id: 3, caption: '공원 산책' },
  ];
  const out = T.rankStable(db, [
    { id: 3, score: 90, matched: ['바다'] },          // 사진에 없는 단서만 → 40점 이하
    { id: 2, score: 80, matched: ['카페', '케이크'] },
    { id: 1, score: 81, matched: ['카페'] },
    { id: 2, score: 10 },                              // 중복
    { id: 99, score: 100 },                            // 없는 사진
  ], ['카페']);
  assert.deepEqual(out.map(x => x.id), [2, 1, 3], '80·81 은 같은 5점 구간 → 실제 단서가 많은 2 가 먼저');
  assert.ok(out.find(x => x.id === 3).score <= 40);
});

test('rankStable: 사용자 답과 맞는 사진을 먼저, 모든 후보에 있는 답은 무시', () => {
  const db = [{ id: 1, caption: '카페', weather: '흐림' }, { id: 2, caption: '카페', weather: '비' }];
  const ranked = [{ id: 1, score: 95, matched: ['카페'] }, { id: 2, score: 60, matched: ['카페'] }];
  assert.deepEqual(T.rankStable(db, ranked, ['카페', 'Q: 날씨? / A: 비']).map(x => x.id), [2, 1]);
  assert.deepEqual(T.rankStable(db, ranked, ['카페', 'Q: 장소? / A: 카페']).map(x => x.id), [1, 2]);
  assert.deepEqual(T.rankStable(db, ranked, ['카페', 'Q: 날씨? / A: 모르겠어요']).map(x => x.id), [1, 2]);
});

test('rankStable: 같은 기억 문장(rq)·확정 키워드(rk 2개 이상)로 찾으면 앞에', () => {
  const db = [
    { id: 1, caption: '케이크', rq: '친구 생일 카페 케이크' },
    { id: 2, caption: '케이크', rk: ['친구', '생일'] },
    { id: 3, caption: '케이크' },
  ];
  const ranked = [{ id: 3, score: 95, matched: ['케이크'] }, { id: 2, score: 70, matched: ['케이크'] }, { id: 1, score: 60, matched: ['케이크'] }];
  assert.deepEqual(T.rankStable(db, ranked, ['친구 생일 카페 케이크']).map(x => x.id), [1, 2, 3]);
  assert.deepEqual(T.rankStable(db, ranked, ['친구 생일 케이크']).map(x => x.id), [2, 3, 1]);
});

test('isDupQ / askedQuestions: 이미 물은 질문 감지', () => {
  const hist = ['카페', 'Q: 날씨는 어땠나요? / A: 비'];
  assert.deepEqual(T.askedQuestions(hist), ['날씨는 어땠나요?']);
  assert.equal(T.isDupQ({ text: '날씨는 어땠나요' }, T.askedQuestions(hist)), true);
  assert.equal(T.isDupQ({ text: '누구랑 갔나요?' }, T.askedQuestions(hist)), false);
});

test('search: AI 순위를 서버가 정리하고 상위 후보(pool)를 돌려줌, 2,000장 초과는 거절', async () => {
  aiReplies({ ranked: [{ id: 2, score: 70, matched: ['케이크'] }, { id: 1, score: 90, matched: ['라떼'] }], question: null });
  const [code, res] = await T.search({ db: [{ id: 1, caption: '라떼' }, { id: 2, caption: '케이크' }], hist: ['카페'] });
  assert.equal(code, 200);
  assert.deepEqual(res.ranked.map(x => x.id), [1, 2]);
  assert.deepEqual(res.pool, [1, 2]);
  assert.equal(calls[0].temperature, 0, '검색은 무작위성을 끈다');
  assert.equal(calls[0].store, false, 'OpenAI 에 저장하지 않음');
  const [bad] = await T.search({ db: Array.from({ length: T.MAX_DB + 1 }, (_, i) => ({ id: i })), hist: ['x'] });
  assert.equal(bad, 400);
});

test('search: 이미 물은 질문을 또 내면 다시 요청하고, 그래도 같으면 질문을 뺌', async () => {
  const dup = { ranked: [], question: { text: '날씨는?', options: ['비', '맑음'] } };
  aiReplies(dup, dup);
  const [, res] = await T.search({ db: [{ id: 1 }], hist: ['카페', 'Q: 날씨는? / A: 비'] });
  assert.equal(calls.length, 2);
  assert.equal(res.question, null);
});

// ── 앨범 ─────────────────────────────────────────────────
const plan = (over = {}) => ({
  title: '테스트', place: { has: false, terms: [] }, time: { from: null, to: null }, kind: 'object',
  topic: null, topic_broad: false, topic_terms: [], mood_cues: [], exclude: null, exclude_terms: [], category: 'memories', ...over,
});

test('album 지명 필터: "성수동" 요청이 행정동 "성수2가3동" 사진과 맞음', async () => {
  aiReplies(plan({ place: { has: true, terms: ['성수동'] } }));
  const db = [
    { id: 1, addr: '서울특별시 성동구 성수2가3동' },
    { id: 2, addr: '서울특별시 마포구 서교동' },
    { id: 3 },
  ];
  const [code, res] = await T.album({ request: '성수동 사진', db });
  assert.equal(code, 200);
  assert.deepEqual(res.ids, [1]);
  assert.equal(calls.length, 1, '주제가 없으면 판정 호출 없음');
});

test('album 지명 필터: 맞는 사진이 없으면 이유를 알려 줌', async () => {
  aiReplies(plan({ place: { has: true, terms: ['부산'] } }));
  const [, res] = await T.album({ request: '부산 사진', db: [{ id: 1, addr: '서울특별시 마포구 서교동' }] });
  assert.deepEqual(res.ids, []);
  assert.match(res.reason, /부산/);
  aiReplies(plan({ place: { has: true, terms: ['부산'] } }));
  const [, res2] = await T.album({ request: '부산 사진', db: [{ id: 1 }] });
  assert.match(res2.reason, /위치 정보/);
});

test('album 날짜 필터', async () => {
  aiReplies(plan({ time: { from: '2025-06-01', to: '2025-08-31' } }));
  const [, res] = await T.album({ request: '작년 여름', db: [{ id: 1, date: '2025-07-01' }, { id: 2, date: '2025-12-01' }] });
  assert.deepEqual(res.ids, [1]);
});

test('album 주제: 이름이 있으면 확실, AI yes 라도 근거가 사진 정보에 없으면 제외', async () => {
  aiReplies(
    plan({ topic: '패스트푸드', topic_terms: ['햄버거'] }),
    { matches: [
      { id: 2, verdict: 'yes', evidence: ['피자'] },   // 근거가 사진 정보에 있음 → 포함
      { id: 3, verdict: 'yes', evidence: ['치킨'] },   // 사진 정보에 없는 근거 → 제외
      { id: 4, verdict: 'maybe', evidence: ['감자'] }, // maybe → 제외
    ] },
  );
  const db = [
    { id: 1, food: ['햄버거'] },
    { id: 2, caption: '피자 한 판' },
    { id: 3, caption: '파스타' },
    { id: 4, caption: '감자튀김' },
  ];
  const [, res] = await T.album({ request: '패스트푸드 모아줘', db });
  assert.deepEqual(res.ids, [1, 2]);
  assert.equal(calls[1].temperature, 0);
});

test('album 분위기: 스크린샷·문서는 빼고 판정', async () => {
  aiReplies(
    plan({ kind: 'mood', topic: '따뜻한 분위기', mood_cues: ['노을', '조명'] }),
    { matches: [{ id: 1, verdict: 'yes', evidence: ['노을'] }] },
  );
  const db = [{ id: 1, caption: '노을', type: 'photo' }, { id: 2, caption: '따뜻한 커피 쿠폰', type: 'screenshot' }];
  const [, res] = await T.album({ request: '따뜻한 분위기', db });
  assert.deepEqual(res.ids, [1]);
  const judged = calls[1].messages[0].content[0].text;
  assert.ok(!judged.includes('쿠폰'), '정보 이미지는 판정에 보내지 않음');
});

test('album 결과 고정: 받은 plan 을 다시 보내면 AI 를 부르지 않고 같은 결과', async () => {
  const db = [{ id: 1, food: ['햄버거'] }, { id: 2, caption: '피자 한 판' }];
  aiReplies(plan({ topic: '패스트푸드', topic_terms: ['햄버거'] }), { matches: [{ id: 2, verdict: 'yes', evidence: ['피자'] }] });
  const [, first] = await T.album({ request: '패스트푸드', db });
  aiReplies();
  const [, again] = await T.album({ request: '패스트푸드', db, plan: first.plan });
  assert.equal(calls.length, 0);
  assert.deepEqual(again.ids, first.ids);
  // 사진 정보가 바뀐 사진만 다시 판정
  aiReplies({ matches: [] });
  const [, changed] = await T.album({ request: '패스트푸드', db: [db[0], { id: 2, caption: '샐러드' }], plan: first.plan });
  assert.equal(calls.length, 1);
  assert.deepEqual(changed.ids, [1]);
});

test('album 제외 조건: AI 가 excluded 로 표시한 사진은 빠짐', async () => {
  aiReplies(plan({ exclude: '음식이 주제인 사진' }), { matches: [], excluded: [2] });
  const [, res] = await T.album({ request: '사진 중 음식은 빼고', db: [{ id: 1, caption: '공원' }, { id: 2, caption: '디저트 카페' }] });
  assert.deepEqual(res.ids, [1]);
});

// ── 사진이 많을 때 (300장 초과) ──────────────────────────────
const bigDb = (n, target) => [
  ...Array.from({ length: n }, (_, i) => ({ id: i + 1, date: '2025-05-01', place: '공원', caption: '공원 산책', kw: ['산책'] })),
  { id: n + 1, date: '2020-01-01', place: '카페', caption: '딸기 케이크와 라떼', food: ['딸기 케이크'], kw: ['카페', '케이크'], ...target },
];

test('lexWords / narrowDb: 조사를 떼고 겹치는 낱말이 많은 사진부터 정해진 수만', () => {
  const w = T.lexWords(['카페에서 먹은 케이크']);
  assert.ok(w.includes('카페') && w.includes('케이크'), JSON.stringify(w));
  assert.ok(!w.includes('먹은'), '일반 낱말 제외');
  const out = T.narrowDb(bigDb(500), w, 300);
  assert.equal(out.length, 300);
  assert.equal(out[0].id, 501, '낱말이 겹치는 사진이 맨 앞');
  assert.equal(T.narrowDb(bigDb(10), w).length, 11, '300장 이하면 그대로');
});

test('search 1,200장: 서버는 받고, AI 에는 300장만 (찾는 사진 포함)', async () => {
  aiReplies({ ranked: [{ id: 1201, score: 95, matched: ['케이크'] }], question: null });
  const [code, res] = await T.search({ db: bigDb(1200), hist: ['카페에서 먹은 딸기 케이크'] });
  assert.equal(code, 200);
  const sent = JSON.parse(calls[0].messages[0].content[0].text.match(/DB:(\[.*?\])\n대화:/s)[1]);
  assert.equal(sent.length, T.AI_DB);
  assert.ok(sent.some(d => d.id === 1201));
  assert.equal(res.ranked[0].id, 1201);
});

test('album 1,200장: 판정은 300장까지, 50장씩 나눠서', async () => {
  const judge = { matches: [{ id: 1201, verdict: 'yes', evidence: ['케이크'] }] };
  aiReplies(plan({ topic: '디저트', topic_terms: [] }), ...Array(6).fill(judge));
  const [code, res] = await T.album({ request: '케이크 사진', db: bigDb(1200) });
  assert.equal(code, 200);
  assert.equal(calls.length, 1 + T.AI_DB / T.PICK_BATCH, '조건 해석 1번 + 판정 6번');
  assert.deepEqual(res.ids, [1201]);
});

test('album 1,200장, 제외 조건만: 판정 못 한 사진도 규칙으로만 거르고 유지', async () => {
  aiReplies(plan({ exclude: '음식이 주제인 사진' }), ...Array(6).fill({ matches: [], excluded: [] }));
  const [, res] = await T.album({ request: '음식은 빼고', db: bigDb(1200) });
  assert.equal(res.ids.length, 1200, '음식 사진(1201)만 빠지고 나머지는 모두');
  assert.ok(!res.ids.includes(1201));
});

test('suggest: 사진이 많으면 최근 300장으로 제안, 2,000장 초과는 거절', async () => {
  aiReplies({ suggestions: ['공원 산책 모음', '공원 산책 모음', '카페 디저트'] });
  const [code, res] = await T.suggest({ db: bigDb(1200) });
  assert.equal(code, 200);
  assert.deepEqual(res.suggestions, ['공원 산책 모음', '카페 디저트'], '중복 제거');
  const sent = JSON.parse(calls[0].messages[0].content[0].text.match(/DB:(\[.*\])\nJSON/s)[1]);
  assert.equal(sent.length, T.AI_DB);
  assert.ok(!sent.some(d => d.id === 1201), '2020년 사진은 최근 300장에 없음');
  assert.equal((await T.suggest({ db: Array.from({ length: T.MAX_DB + 1 }, (_, i) => ({ id: i })) }))[0], 400);
});

test('grounded / photoPrint', () => {
  assert.deepEqual(T.grounded({ caption: '비 오는 카페' }, ['caption: 카페', '바다']), ['카페']);
  assert.equal(T.photoPrint({ id: 1, caption: 'a' }), T.photoPrint({ id: 1, caption: 'a' }));
  assert.notEqual(T.photoPrint({ id: 1, caption: 'a' }), T.photoPrint({ id: 1, caption: 'b' }));
});

// ── 찾은 기억 키워드 (모순 검사) ─────────────────────────────
test('conflictsWithPhoto: 계절·날씨·시간대가 사진과 다르면 모순', () => {
  const photo = { date: '2025-12-20', weather: '비', time: '저녁' };
  assert.equal(T.conflictsWithPhoto('여름', photo), true);
  assert.equal(T.conflictsWithPhoto('겨울', photo), false);
  assert.equal(T.conflictsWithPhoto('맑은', photo), true);
  assert.equal(T.conflictsWithPhoto('비', photo), false);
  assert.equal(T.conflictsWithPhoto('밤', photo), true);
  assert.equal(T.conflictsWithPhoto('친구', photo), false);
  assert.equal(T.conflictsWithPhoto('여름', {}), false, '날짜가 없으면 판단하지 않음');
});

test('recall: 말한 낱말만, 사진에 이미 있거나 어긋나는 낱말·일반 낱말은 제외', async () => {
  aiReplies({ keywords: [
    { word: '친구', conflict: 'unknown' },
    { word: '여름', conflict: 'no' },       // 12월 사진 → 규칙으로 제외
    { word: '바닷가', conflict: 'yes' },    // AI 가 모순 판정 → 제외
    { word: '케이크', conflict: 'no' },     // 이미 사진 정보에 있음 → 제외
    { word: '엄마', conflict: 'unknown' },  // 말하지 않은 낱말 → 제외
    { word: '먹은', conflict: 'no' },       // 일반 낱말 → 제외
    { word: '생일', conflict: 'unknown' },
  ] });
  const photo = { id: 3, date: '2025-12-20', caption: '케이크와 커피', weather: '비', time: '저녁', place: '카페' };
  const [code, res] = await T.recall({ photo, query: '여름에 바닷가에서 친구 생일에 먹은 케이크' });
  assert.equal(code, 200);
  assert.deepEqual(res.keywords, ['친구', '생일']);
});

test('recall: 잘못된 요청은 400', async () => {
  assert.equal((await T.recall({ photo: { id: 1 } }))[0], 400);
  assert.equal((await T.recall({ query: 'x', photo: [] }))[0], 400);
});

// ── 라우팅 · 요청 처리 ──────────────────────────────────────
const fakeReq = (method, body) => Object.assign(Readable.from(body == null ? [] : [body]), {
  method, headers: { 'x-forwarded-for': '10.0.0.' + Math.floor(Math.random() * 250) }, socket: {},
});
const fakeRes = () => {
  const r = { status: 0, body: '', headers: {}, setHeader(k, v) { this.headers[k] = v; }, writeHead(s) { this.status = s; }, end(b = '') { this.body = String(b); } };
  return r;
};

test('handleApi: health · 없는 경로 404 · 잘못된 JSON 400 · 잘못된 이미지 400', async () => {
  let res = fakeRes();
  await handleApi(fakeReq('GET'), res, 'health');
  assert.equal(res.status, 200);
  assert.equal(JSON.parse(res.body).key, true);
  assert.ok(!res.body.includes('sk-test'), '키 내용은 내려보내지 않음');

  res = fakeRes();
  await handleApi(fakeReq('POST', '{}'), res, 'nope');
  assert.equal(res.status, 404);

  res = fakeRes();
  await handleApi(fakeReq('POST', '{not json'), res, 'search');
  assert.equal(res.status, 400);

  res = fakeRes();
  await handleApi(fakeReq('POST', JSON.stringify({ image: 'http://x' })), res, 'analyze');
  assert.equal(res.status, 400);
  assert.equal(JSON.parse(res.body).error, 'bad_image');
});

// ── 임베딩 (/api/embed, 분석 응답의 embedding) ─────────────────────
test('embed: 단건 · 배치(빈 항목은 null) · 256차원 · text-embedding-3-small', async () => {
  const [c1, one] = await T.embed({ text: '비 오는 날 카페' });
  assert.equal(c1, 200);
  assert.equal(one.embedding.length, T.EMBED_DIM);
  assert.equal(embedCalls[0].model, 'text-embedding-3-small');
  assert.equal(embedCalls[0].dimensions, 256);
  const [c2, many] = await T.embed({ texts: ['카페', '', '공원'] });
  assert.equal(c2, 200);
  assert.equal(many.embeddings.length, 3);
  assert.equal(many.embeddings[1], null);
  assert.equal(many.embeddings[0].length, 256);
  assert.deepEqual(embedCalls[1].input, ['카페', '공원'], '빈 항목은 보내지 않음');
});

test('embed: 잘못된 요청은 400 (빈 글, 50개 초과)', async () => {
  assert.equal((await T.embed({ text: '  ' }))[0], 400);
  assert.equal((await T.embed({ texts: [] }))[0], 400);
  assert.equal((await T.embed({ texts: Array(51).fill('a') }))[0], 400);
  assert.equal((await T.embed({}))[0], 400);
});

test('analyze: 응답에 임베딩 포함, 임베딩이 실패해도 분석은 성공', async () => {
  const ai = { image_type: 'photo', caption: '창가의 딸기 케이크', main_topic: '디저트', food: ['케이크'], structured_data: { 메뉴: ['딸기 케이크'] } };
  aiReplies(ai);
  const [code, res] = await T.analyze({ image: 'data:image/jpeg;base64,AAAA' });
  assert.equal(code, 200);
  assert.equal(res.embedding.length, 256);
  assert.ok(embedCalls[0].input[0].includes('창가의 딸기 케이크') && embedCalls[0].input[0].includes('디저트'));
  embedFail = true;
  aiReplies(ai);
  const [code2, res2] = await T.analyze({ image: 'data:image/jpeg;base64,AAAA' });
  assert.equal(code2, 200);
  assert.equal(res2.embedding, undefined);
  assert.equal(res2.caption, '창가의 딸기 케이크');
});

test('analysisEmbedText: 설명·키워드·구조화 정보를 합침', () => {
  const t = T.analysisEmbedText(T.normalizeAnalysis({ caption: '영수증', search_keywords: ['지출'], structured_data: { 항목: [{ 이름: '라떼' }] } }));
  for (const w of ['영수증', '지출', '라떼']) assert.ok(t.includes(w), t);
});

test('handleApi: embed 경로 등록', async () => {
  const res = fakeRes();
  await handleApi(fakeReq('POST', JSON.stringify({ text: '카페' })), res, 'embed');
  assert.equal(res.status, 200);
  assert.equal(JSON.parse(res.body).embedding.length, 256);
});
