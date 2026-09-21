// معاينة الموقع على الجهاز عبر HTTP؛ لا يتيح ملفات قاعدة البيانات أو أدوات التطوير.
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(fileURLToPath(new URL('../', import.meta.url)));
const port = 4173;
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf', '.mp4': 'video/mp4' };
const server = http.createServer(async (req, res) => {
  function fail(code) { res.writeHead(code, { 'Content-Type': 'text/plain; charset=utf-8' }); res.end(http.STATUS_CODES[code]); }
  if (!['127.0.0.1:4173', 'localhost:4173'].includes(req.headers.host)) return fail(403);
  if (!['GET', 'HEAD'].includes(req.method)) return fail(405);
  try {
    let name = decodeURIComponent(new URL(req.url, 'http://127.0.0.1:4173').pathname).slice(1) || 'index.html';
    const parts = name.split('/');
    const extension = path.extname(name).toLowerCase();
    if (name.includes('\\') || name.includes('\0') || parts.some(part => part.startsWith('.')) || !types[extension]) return fail(404);
    const rootPage = parts.length === 1 && /^(?:index|web-[a-z-]+)\.html$/.test(name);
    const rootAsset = parts.length === 1 && ['.js', '.css', '.ico'].includes(extension);
    const media = parts[0] === 'assets' && !['.html', '.js'].includes(extension);
    if (!rootPage && !rootAsset && !media) return fail(404);
    const target = await fs.realpath(path.join(root, name));
    if (!target.startsWith(root + path.sep)) return fail(404);
    const body = await fs.readFile(target);
    res.writeHead(200, { 'Content-Type': types[extension], 'Content-Length': body.length, 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'strict-origin-when-cross-origin', 'Cache-Control': 'no-cache' });
    res.end(req.method === 'HEAD' ? undefined : body);
  } catch { fail(404); }
});
server.on('error', error => { console.error(error.code === 'EADDRINUSE' ? 'Port 4173 is already in use.' : error.message); process.exitCode = 1; });
server.listen(port, '127.0.0.1', () => console.log('Website preview: http://127.0.0.1:4173/web-addresses.html'));
