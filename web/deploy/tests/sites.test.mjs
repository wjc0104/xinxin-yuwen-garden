import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile, readdir, mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve, join, dirname, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildFiles, mediaAllowlist, prepareSites, ASSETS, PROJECT_ID} from '../prepare-sites.mjs';
import {createSiteHandler} from '../site-handler.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const filesPromise = buildFiles();
const library = JSON.parse(await readFile(join(root, 'App/Resources/library.json'), 'utf8'));
const catalog = JSON.parse(await readFile(join(root, 'App/Resources/catalog.json'), 'utf8'));
const privateCache = response => assert.equal(response.headers.get('cache-control'), 'private, no-store');
const request = (path, options) => new Request('https://private.example' + path, options);
async function temporary(t) {
  const parent = resolve(tmpdir());
  const folder = await mkdtemp(join(parent, 'xinyu-sites-adapter-'));
  t.after(async () => {
    const target = resolve(folder);
    if (!target.startsWith(parent + sep) || !target.split(sep).at(-1).startsWith('xinyu-sites-adapter-')) throw new Error('Unsafe cleanup target');
    await rm(target, {recursive: true, force: true});
  });
  return folder;
}

test('explicit assets cover current dist and contain only sanitized original 198-lesson data', async () => {
  const files = await filesPromise;
  const assets = JSON.parse(files['lib/xinyu/static-assets.json']);
  const actual = (await readdir(join(root, 'web/dist'), {recursive: true, withFileTypes: true}))
    .filter(entry => entry.isFile()).map(entry => join(entry.parentPath ?? entry.path, entry.name)
      .slice(join(root, 'web/dist').length + 1).replaceAll('\\', '/')).sort();
  assert.deepEqual(Object.keys(ASSETS).sort(), actual);
  assert.deepEqual(Object.keys(assets).sort(), actual.map(path => '/' + path).sort());
  const data = JSON.parse(assets['/data/catalogue.json'].body);
  assert.equal(data.lessons.length, 198);
  assert.equal(new Set(data.lessons.map(row => row.id)).size, 198);
  assert.equal(data.books.length, 6);
  assert.equal(data.resources.length, 1163);
  for (const item of data.resources) {
    assert.deepEqual(Object.keys(item).sort(), ['id','lessonID','title','kind','body','url','source','isPaid','category','durationSeconds','checkedAt','summary'].sort());
    assert.ok(!item.body || ['欣语备课提纲','欣语原创练习'].includes(item.source));
  }
  assert.ok(assets['/player.js']);
  assert.ok(!Object.keys(assets).some(path => /App\/|\.git|scratch|\.env|library\.json|localFile/.test(path)));
});

test('media whitelist preserves original CIDs, strips private fields and URL parameters', async () => {
  const files = await filesPromise;
  const resources = JSON.parse(files['lib/xinyu/media-allowlist.json']);
  assert.equal(resources.length, 627);
  for (const item of resources) {
    assert.deepEqual(Object.keys(item).sort(), ['id','kind','url','videoCID','isPaid'].sort());
    assert.equal(item.videoCID, library.find(original => original.id === item.id).videoCID);
    assert.equal(item.isPaid, false);
  }
  const row = {...library.find(item => item.kind === 'video'), localFile: 'PRIVATE_SENTINEL', email: 'SECRET_SENTINEL'};
  const url = new URL(row.url); url.searchParams.set('token', 'SECRET_SENTINEL'); row.url = url.href;
  const filtered = mediaAllowlist([row], new Set([row.lessonID]));
  assert.doesNotMatch(JSON.stringify(filtered), /SECRET_SENTINEL|PRIVATE_SENTINEL|localFile|email|token/);
  assert.deepEqual(mediaAllowlist([{...row, isPaid: true}], new Set([row.lessonID])), []);
  assert.throws(() => mediaAllowlist([{...row, url: 'https://evil.example/video/BV1234567890'}], new Set([row.lessonID])));
});

test('extra private original fields cannot enter generated artifacts', async () => {
  const injected = library.map(item => ({...item, privateNotes: 'PRIVATE_SENTINEL', localFile: 'PRIVATE_SENTINEL', ownerEmail: 'SECRET_SENTINEL'}));
  const files = await buildFiles({catalog: {...catalog, ownerEmail: 'SECRET_SENTINEL'}, library: injected});
  assert.doesNotMatch(JSON.stringify(files), /PRIVATE_SENTINEL|SECRET_SENTINEL/);
});

test('unknown dist files are omitted and private fields in catalogue fail closed', async t => {
  const dist = await temporary(t);
  const assets = JSON.parse((await filesPromise)['lib/xinyu/static-assets.json']);
  for (const [path, asset] of Object.entries(assets)) {
    const target = join(dist, path.slice(1)); await mkdir(dirname(target), {recursive:true});
    await writeFile(target, asset.body);
  }
  await writeFile(join(dist, '.env'), 'TOKEN=PRIVATE_SENTINEL');
  const clean = await buildFiles({dist});
  assert.doesNotMatch(JSON.stringify(clean), /PRIVATE_SENTINEL/);
  const data = JSON.parse(assets['/data/catalogue.json'].body); data.ownerEmail = 'PRIVATE_SENTINEL';
  await writeFile(join(dist, 'data/catalogue.json'), JSON.stringify(data));
  await assert.rejects(buildFiles({dist}), /sanitized original/);
});

test('generated route retains official auth and raw HTML relative asset paths', async () => {
  const files = await filesPromise;
  assert.match(files['app/[[...path]]/route.ts'], /from '\.\.\/chatgpt-auth'/);
  assert.match(files['app/[[...path]]/route.ts'], /dynamic = 'force-dynamic'/);
  assert.doesNotMatch(files['app/[[...path]]/route.ts'], /debug|local-user|oauth/i);
  assert.match(files['app/layout.tsx'], /lang="zh-CN"/);
  assert.doesNotMatch(files['app/layout.tsx'], /codex-preview|Starter Project/);
  const assets = JSON.parse(files['lib/xinyu/static-assets.json']);
  assert.equal(assets['/index.html'].body, await readFile(join(root, 'web/dist/index.html'), 'utf8'));
  assert.match(assets['/index.html'].body, /src="\.\/app.js"/);
  assert.match(assets['/index.html'].body, /<link rel="manifest" href="\.\/manifest\.webmanifest" crossorigin="use-credentials">/);
  assert.match(assets['/index.html'].body, /frame-src 'none'/);
  assert.match(assets['/sw.js'].body, /!response.ok/);
  assert.match(assets['/sw.js'].body, /response.redirected/);
});

test('anonymous root redirects; assets/API reject even forged local identity', async () => {
  let called = 0;
  const handle = createSiteHandler({assets: {}, resources: [], getUser: async () => null,
    signInPath: () => '/signin-with-chatgpt?return_to=%2F', createMediaHandler: () => {called++;}});
  const rootResponse = await handle(request('/'));
  assert.equal(rootResponse.status, 302); privateCache(rootResponse);
  assert.equal(rootResponse.headers.get('location'), '/signin-with-chatgpt?return_to=%2F');
  for (const path of ['/index.html','/app.js','/data/catalogue.json','/api/video/id','/api/video/id/stream']) {
    const response = await handle(request(path, {headers: {'x-debug-user': 'owner', 'oai-authenticated-user-id': 'forged'}}));
    assert.equal(response.status, 401); privateCache(response);
  }
  assert.equal(called, 0);
});

test('authenticated static routing has exact allowlist, HEAD and no-store on every response', async () => {
  const assets = JSON.parse((await filesPromise)['lib/xinyu/static-assets.json']);
  const handle = createSiteHandler({assets, resources: [], getUser: async () => ({userId:'owner'}),
    signInPath: () => '/', createMediaHandler: () => {throw new Error('Unexpected media');}});
  for (const path of ['/', ...Object.keys(assets)]) {
    const response = await handle(request(path)); assert.equal(response.status, 200); privateCache(response);
    assert.equal(await response.text(), assets[path === '/' ? '/index.html' : path].body);
  }
  for (const path of ['/App/Resources/library.json','/.git/config','/.env','/scratch','/toString','/%61pp.js','/app.js?x=1','/unknown']) {
    const response = await handle(request(path)); assert.equal(response.status, 404); privateCache(response);
  }
  const head = await handle(request('/app.js', {method:'HEAD'})); assert.equal(await head.text(), ''); privateCache(head);
  const post = await handle(request('/app.js', {method:'POST'})); assert.equal(post.status, 405); privateCache(post);
  assert.equal((await handle(request('/sw.js'))).headers.get('service-worker-allowed'), '/');
});

test('media receives request-local authorization and original range request', async () => {
  const resources = [{id:'original', videoCID:123}]; let current = {userId:'owner'}; let captured;
  const handle = createSiteHandler({assets:{}, resources, getUser: async () => current, signInPath: () => '/',
    createMediaHandler: options => {captured = options; return async req => {
      assert.equal(req.headers.get('range'), 'bytes=0-1');
      assert.equal(await options.authorize(), true);
      return new Response('ab', {status:206, headers:{'Content-Range':'bytes 0-1/10'}});
    };}});
  const response = await handle(request('/api/video/original/stream', {headers:{Range:'bytes=0-1'}}));
  assert.equal(response.status, 206); privateCache(response); assert.equal(response.headers.get('content-range'), 'bytes 0-1/10');
  assert.equal(captured.resources, resources);
  current = null;
  assert.equal((await handle(request('/api/video/original/stream'))).status, 401);
});

test('preparation preserves identity/auth, backs up exact files, removes only starter page', async t => {
  const dest = await temporary(t);
  await mkdir(join(dest, '.openai')); await mkdir(join(dest, 'app')); await mkdir(join(dest, 'public'));
  const manifest = JSON.stringify({project_id: PROJECT_ID, d1:null, r2:null});
  const auth = 'export async function getChatGPTUser() {}\nexport function chatGPTSignInPath() {}';
  await writeFile(join(dest, '.openai/hosting.json'), manifest);
  await writeFile(join(dest, '.gitignore'), '/.sites-runtime/\n');
  await writeFile(join(dest, 'app/chatgpt-auth.ts'), auth);
  await writeFile(join(dest, 'app/page.tsx'), 'ORIGINAL_PAGE');
  await writeFile(join(dest, 'app/layout.tsx'), 'ORIGINAL_LAYOUT');
  await writeFile(join(dest, 'public/keep.txt'), 'KEEP');
  const result = await prepareSites(dest);
  assert.equal(await readFile(join(dest, '.openai/hosting.json'), 'utf8'), manifest);
  assert.equal(await readFile(join(dest, 'app/chatgpt-auth.ts'), 'utf8'), auth);
  assert.equal(await readFile(join(dest, result.backup, 'app/page.tsx'), 'utf8'), 'ORIGINAL_PAGE');
  assert.equal(await readFile(join(dest, result.backup, 'app/layout.tsx'), 'utf8'), 'ORIGINAL_LAYOUT');
  await assert.rejects(readFile(join(dest, 'app/page.tsx')), {code:'ENOENT'});
  assert.equal(await readFile(join(dest, 'public/keep.txt'), 'utf8'), 'KEEP');
  assert.equal(result.files.length, 6);
  await writeFile(join(dest, '.openai/hosting.json'), JSON.stringify({project_id:'wrong'}));
  await assert.rejects(prepareSites(dest), /identity/);
});
