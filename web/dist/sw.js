/* Only public, same-origin application assets belong in this cache. */
importScripts('./version.js');
const BASE = new URL('./', self.location.href);
const PREFIX = `xinyu-public:${BASE.pathname}:`;
const CACHE = PREFIX + self.XINYU_VERSION;
const ASSETS = new Map(Object.entries({
  'index.html': 'text/html', 'app.js': 'javascript', 'core.js': 'javascript',
  'storage.js': 'javascript', 'player.js': 'javascript', 'style.css': 'text/css',
  'manifest.webmanifest': 'json', 'icon.svg': 'image/svg+xml',
  'data/catalogue.json': 'application/json'
}).map(([path,type]) => [new URL(path,BASE).href,type]));

async function checkedResponse(url) {
  const response = await fetch(url, {cache:'no-store', credentials:'same-origin', redirect:'error'});
  if (!response.ok || response.redirected || response.url !== url || response.type === 'opaque' ||
      !response.headers.get('content-type')?.includes(ASSETS.get(url))) throw new Error('Unexpected static response');
  if (url === new URL('index.html',BASE).href && !(await response.clone().text()).includes('<meta name="xinyu-app" content="private-web-v1">')) throw new Error('Not application shell');
  if (url === new URL('data/catalogue.json',BASE).href) {
    const data = await response.clone().json();
    if (data.schemaVersion !== 1 || data.lessons?.length !== 198 || !Array.isArray(data.resources) || !data.dataVersion) throw new Error('Not public catalogue');
  }
  return response;
}
self.addEventListener('install', event => event.waitUntil((async () => {
  // Validate everything before writing: never retain a login page or partial new cache.
  const entries = await Promise.all([...ASSETS.keys()].map(async url => [url, await checkedResponse(url)]));
  const cache = await caches.open(CACHE);
  try { await Promise.all(entries.map(([url,response]) => cache.put(url,response))); }
  catch (error) { await caches.delete(CACHE); throw error; }
  // No skipWaiting: an update must not interrupt open editors.
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const key of await caches.keys()) if (key.startsWith(PREFIX) && key !== CACHE) await caches.delete(key);
  // No clients.claim and no IndexedDB access; existing pages and notes stay untouched.
})()));
self.addEventListener('fetch', event => {
  const request = event.request, url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== BASE.origin || url.search || request.cache === 'no-store') return;
  const key = url.href === BASE.href ? new URL('index.html',BASE).href : url.href;
  if (!ASSETS.has(key)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(key);
    return cached || checkedResponse(key);
  })());
});
