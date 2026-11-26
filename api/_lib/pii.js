// 개인 식별 정보 제거 · 구조화 정보 크기 제한

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

export { capJson, PII_KEY, NAME_KEY, isPiiKey, scrubPII, piiValues, scrubData };
