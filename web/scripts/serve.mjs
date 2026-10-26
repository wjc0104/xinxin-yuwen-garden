import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, relative, extname, isAbsolute } from 'node:path';
const root = fileURLToPath(new URL('../dist/',import.meta.url));
const types = {'.html':'text/html','.js':'text/javascript','.css':'text/css','.json':'application/json','.webmanifest':'application/manifest+json','.svg':'image/svg+xml'};
const server = createServer(async (request,response) => {
  try {
    if (!['GET','HEAD'].includes(request.method)) { response.writeHead(405).end(); return; }
    const pathname = decodeURIComponent(new URL(request.url,'http://localhost').pathname);
    if (pathname.includes('\\') || pathname.includes('\0')) { response.writeHead(400).end(); return; }
    const file = resolve(root,`.${pathname === '/' ? '/index.html' : pathname}`), rel = relative(root,file);
    if (rel.startsWith('..') || isAbsolute(rel)) { response.writeHead(403).end(); return; }
    const body = await readFile(file);
    response.writeHead(200, {'Content-Type':`${types[extname(file)] || 'application/octet-stream'}; charset=utf-8`,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
    response.end(request.method === 'HEAD' ? undefined : body);
  } catch { response.writeHead(404).end('Not found'); }
});
server.listen(Number(process.env.PORT || 4173),'127.0.0.1',()=>console.log(`Local only: http://127.0.0.1:${server.address().port}`));
