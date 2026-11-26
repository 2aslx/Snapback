// 찾은 기억 키워드 (/api/recall): 모순 검사
import { ask } from './openai.js';
import { scrubPII } from './pii.js';
import { slimPhoto, photoWords } from './photos.js';

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

export { SEASONS, WEATHER_GROUPS, TIME_GROUPS, conflictsWithPhoto, GENERIC_RECALL, recallPrompt, recall };
