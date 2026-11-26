// 기록 초안 (/api/record)
import { ask } from './openai.js';

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

export { PLACE_KINDS, RECORD, record };
