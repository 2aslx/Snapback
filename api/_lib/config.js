// 환경 설정 · 공용 도구 (API 키 확인·오류 코드·로그 키 가림)

const MODEL = process.env.OPENAI_MODEL || 'gpt-4o-mini';
const key = () => process.env.OPENAI_API_KEY || '';
// 키 모양만 확인 (키 내용은 절대 출력하지 않음)
const keyOk = () => /^sk-[\w-]{20,}$/.test(key());

const fail = c => Object.assign(new Error(c), { code: c });          // 클라이언트로 보낼 오류 코드
const hide = s => String(s).replace(/sk-[\w\-*.]+/g, 'sk-***').replace(/AIza[\w-]+/g, 'AIza***'); // 로그에 키가 섞여도 가림
const mapsKey = () => process.env.GOOGLE_MAPS_API_KEY || '';

export { MODEL, key, keyOk, fail, hide, mapsKey };
