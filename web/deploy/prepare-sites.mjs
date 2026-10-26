import {readFile, writeFile, mkdir, lstat, realpath, copyFile, unlink} from 'node:fs/promises';
import {resolve, dirname, join, relative, isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {exportData} from '../scripts/export-data.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../..');
export const PROJECT_ID = 'appgprj_6adf7c5dec908191ab0ddf12b586421d';
export const ASSETS = Object.freeze({
  'index.html': 'text/html; charset=utf-8',
  'app.js': 'text/javascript; charset=utf-8',
  'core.js': 'text/javascript; charset=utf-8',
  'storage.js': 'text/javascript; charset=utf-8',
  'player.js': 'text/javascript; charset=utf-8',
  'style.css': 'text/css; charset=utf-8',
  'manifest.webmanifest': 'application/manifest+json; charset=utf-8',
  'sw.js': 'text/javascript; charset=utf-8',
  'version.js': 'text/javascript; charset=utf-8',
  'icon.svg': 'image/svg+xml',
  'data/catalogue.json': 'application/json; charset=utf-8'
});

export function mediaAllowlist(library, lessonIDs) {
  const seen = new Set();
  return library.filter(item => lessonIDs.has(item.lessonID) && item.kind === 'video' && item.isPaid === false).map(item => {
    const url = new URL(item.url);
    const match = /^\/video\/(BV[A-Za-z0-9]{10})\/?$/.exec(url.pathname);
    const pages = url.searchParams.getAll('p');
    const page = Number(pages[0] || 1);
    if (!/^[\w-]{1,160}$/.test(item.id) || seen.has(item.id) ||
        url.protocol !== 'https:' || !['www.bilibili.com', 'bilibili.com'].includes(url.hostname) ||
        url.username || url.password || url.port || url.hash || !match || pages.length > 1 ||
        !Number.isSafeInteger(page) || page < 1 || page > 5000 ||
        !Number.isSafeInteger(item.videoCID) || item.videoCID < 1) throw new Error('Invalid original media reference');
    seen.add(item.id);
    // Drop all unrelated query parameters as well as thumbnails, localFile and bodies.
    return {id: item.id, kind: 'video', url: `https://www.bilibili.com/video/${match[1]}?p=${page}`,
      videoCID: item.videoCID, isPaid: false};
  });
}

async function safeFile(base, name) {
  const file = resolve(base, name);
  const rel = relative(base, file);
  if (!rel || rel.startsWith('..') || isAbsolute(rel)) throw new Error('Path outside selected directory');
  let current = base;
  for (const part of rel.split(/[\\/]/)) {
    current = join(current, part);
    try { if ((await lstat(current)).isSymbolicLink()) throw new Error('Symlink not allowed in deployment input/output'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  return file;
}

export async function buildFiles({dist = resolve(root, 'web/dist'), catalog, library} = {}) {
  catalog ??= JSON.parse(await readFile(resolve(root, 'App/Resources/catalog.json'), 'utf8'));
  library ??= JSON.parse(await readFile(resolve(root, 'App/Resources/library.json'), 'utf8'));
  const expected = exportData(catalog, library);
  const assets = {};
  for (const [name, type] of Object.entries(ASSETS)) {
    assets['/' + name] = {type, body: await readFile(await safeFile(dist, name), 'utf8')};
  }
  // Stale exports or additional private fields are a hard failure, never copied blindly.
  if (!isDeepStrictEqual(JSON.parse(assets['/data/catalogue.json'].body), expected)) {
    throw new Error('Public catalogue differs from sanitized original 198-lesson export; run web/scripts/export-data.mjs');
  }
  const resources = mediaAllowlist(library, new Set(expected.lessons.map(item => item.id)));
  const route = `import {getChatGPTUser, chatGPTSignInPath} from '../chatgpt-auth';
import {createMediaHandler} from '../../lib/xinyu/media.mjs';
import {createSiteHandler} from '../../lib/xinyu/site-handler.mjs';
import assets from '../../lib/xinyu/static-assets.json';
import resources from '../../lib/xinyu/media-allowlist.json';

export const dynamic = 'force-dynamic';
const handle = createSiteHandler({assets, resources, createMediaHandler,
  getUser: getChatGPTUser, signInPath: chatGPTSignInPath});
export const GET = handle;
export const HEAD = handle;
export const POST = handle;
export const PUT = handle;
export const PATCH = handle;
export const DELETE = handle;
export const OPTIONS = handle;
`;
  const layout = `import type {Metadata} from 'next';
export const metadata: Metadata = {
  title: '欣语 · 语文学习', description: '个人语文备课与学习空间',
  icons: {icon: '/icon.svg'}
};
export default function RootLayout({children}: Readonly<{children: React.ReactNode}>) {
  return <html lang="zh-CN"><body>{children}</body></html>;
}
`;
  return {
    'app/[[...path]]/route.ts': route,
    'app/layout.tsx': layout,
    'lib/xinyu/static-assets.json': JSON.stringify(assets),
    'lib/xinyu/media-allowlist.json': JSON.stringify(resources),
    'lib/xinyu/site-handler.mjs': await readFile(join(here, 'site-handler.mjs'), 'utf8'),
    'lib/xinyu/media.mjs': await readFile(resolve(root, 'web/server/media.mjs'), 'utf8')
  };
}

export async function prepareSites(destination) {
  const dest = await realpath(resolve(destination));
  if (dest === root || dest.startsWith(root + '\\') || dest.startsWith(root + '/')) {
    throw new Error('Destination must be the separate existing Sites checkout, not the native repository');
  }
  const manifest = JSON.parse(await readFile(await safeFile(dest, '.openai/hosting.json'), 'utf8'));
  if (manifest.project_id !== PROJECT_ID || manifest.static) throw new Error('Expected existing private Vinext Site identity');
  const auth = await readFile(await safeFile(dest, 'app/chatgpt-auth.ts'), 'utf8');
  if (!auth.includes('export async function getChatGPTUser') || !auth.includes('export function chatGPTSignInPath')) {
    throw new Error('Official Sites auth helper is missing');
  }
  const ignored = await readFile(join(dest, '.gitignore'), 'utf8');
  if (!/^\/\.sites-runtime\/$/m.test(ignored.replace(/\r/g, ''))) throw new Error('Backup folder must be ignored');
  const files = await buildFiles();
  const backup = `.sites-runtime/xinyu-adapter-backups/${Date.now()}-${randomUUID()}`;
  const names = [...Object.keys(files), 'app/page.tsx'];
  // Validate every explicit path and back up every existing target before changing any.
  for (const name of names) {
    const target = await safeFile(dest, name);
    try {
      const info = await lstat(target);
      if (!info.isFile()) throw new Error('Expected file at deployment target');
      const backupPath = await safeFile(dest, `${backup}/${name}`);
      await mkdir(dirname(backupPath), {recursive: true});
      await copyFile(target, backupPath);
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  for (const [name, body] of Object.entries(files)) {
    const target = await safeFile(dest, name);
    await mkdir(dirname(target), {recursive: true});
    await writeFile(target, body, 'utf8');
  }
  // Exactly this starter page conflicts with the root optional catch-all. No recursive removal.
  await unlink(await safeFile(dest, 'app/page.tsx')).catch(error => {if (error.code !== 'ENOENT') throw error;});
  return {projectId: PROJECT_ID, files: Object.keys(files), backup};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 3) throw new Error('Usage: node web/deploy/prepare-sites.mjs <existing-sites-checkout>');
  console.log(JSON.stringify(await prepareSites(process.argv[2]), null, 2));
}
