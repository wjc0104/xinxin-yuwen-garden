// This module receives only sanitized generated data, never native application state.
export function createSiteHandler({assets, resources, createMediaHandler, getUser, signInPath}) {
  const privateHeaders = {
    'Cache-Control': 'private, no-store',
    'Vary': 'Cookie, oai-authenticated-user-id, oai-authenticated-user-email',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'strict-origin-when-cross-origin'
  };
  const error = (status, message) => Response.json({error: message}, {status, headers: privateHeaders});
  return async request => {
    const url = new URL(request.url);
    // Only Sites' server-side helper supplies identity. Never accept a debug header.
    let user = null;
    try { user = await getUser(); } catch { /* Fail closed. */ }
    if (!user) {
      if (url.pathname === '/' && ['GET', 'HEAD'].includes(request.method)) {
        return new Response(null, {status: 302, headers: {...privateHeaders, Location: signInPath('/')}});
      }
      return error(401, '请先登录已授权的所有者账号。');
    }
    if (url.pathname.startsWith('/api/video/')) {
      // Request-local closure: an identity can never leak into another request.
      const handler = createMediaHandler({resources, authorize: async () => Boolean(user)});
      const response = await handler(request);
      const headers = new Headers(response.headers);
      for (const [key, value] of Object.entries(privateHeaders)) headers.set(key, value);
      return new Response(response.body, {status: response.status, statusText: response.statusText, headers});
    }
    if (!['GET', 'HEAD'].includes(request.method)) return error(405, '仅支持读取。');
    const path = url.pathname === '/' ? '/index.html' : url.pathname;
    // Exact lookup only; no filesystem paths, URL decoding, or SPA fallback.
    if (url.search || !Object.hasOwn(assets, path)) return error(404, '未找到资源。');
    const asset = assets[path];
    return new Response(request.method === 'HEAD' ? null : asset.body, {
      headers: {...privateHeaders, 'Content-Type': asset.type,
        ...(path === '/sw.js' ? {'Service-Worker-Allowed': '/'} : {})}
    });
  };
}
