// 기억(Memory) — 로컬 개발 서버: 브라우저/앱 → 이 서버 → OpenAI API. API 키는 서버에만 둔다.
// API 로직은 api/_core.js 에 있고, Vercel 배포 시에는 api/*.js 함수가 같은 로직을 사용한다.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { handleApi, keyOk } from './api/_core.js';

const PORT = process.env.PORT || 3000;
const ROOT = path.dirname(fileURLToPath(import.meta.url));
const FLUTTER_WEB = path.join(ROOT, 'flutter_app', 'build', 'web');
const PUB = fs.existsSync(path.join(FLUTTER_WEB, 'index.html')) ? FLUTTER_WEB : path.join(ROOT, 'public');
if (!process.env.OPENAI_API_KEY) { console.error('OPENAI_API_KEY 가 없어요. .env 파일을 확인하세요.'); process.exit(1); }
if (!keyOk()) console.warn('⚠️  .env 의 OPENAI_API_KEY 가 예시 문구 그대로이거나 형식이 이상해요. 실제 키로 바꾼 뒤 서버를 다시 시작하세요.');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

http.createServer(async (req, res) => {
  const url = req.url.split('?')[0];
  if (url.startsWith('/api/')) return handleApi(req, res, url.slice(5));
  try {
    const f = path.join(PUB, url === '/' ? 'index.html' : path.normalize(url).replace(/^(\.\.[/\\])+/, ''));
    if (!f.startsWith(PUB) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
    fs.createReadStream(f).pipe(res);
  } catch {
    try { res.writeHead(500); res.end('server error'); } catch {}
  }
}).listen(PORT, () => console.log('http://localhost:' + PORT));
