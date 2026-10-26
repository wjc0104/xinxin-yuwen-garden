# Owner-private Sites adapter

This is a source generator, not a publisher. It uses the existing, separately
registered Vinext checkout for `appgprj_6adf7c5dec908191ab0ddf12b586421d`.
Do not upload this native repository or change the Site audience.

After the web implementation and data export are final, the main task may run:

```powershell
node web/deploy/prepare-sites.mjs C:\Users\wm14\Desktop\xinyu-web-private-20261027
```

The command needs filesystem approval for that external checkout. It writes only
six named files there and removes exactly `app/page.tsx`. Existing versions of
these targets are backed up under its ignored `.sites-runtime` directory first.
The Site identity, official `app/chatgpt-auth.ts`, dependencies, Vite/Sites build
integration and other starter files remain untouched.

Generated files:

- `app/[[...path]]/route.ts`: dynamic root/assets/API route, official auth only.
- `app/layout.tsx`: Chinese metadata; no starter preview metadata.
- `lib/xinyu/static-assets.json`: eleven explicitly named text assets, including
  `player.js` and the original sanitized 198-lesson public catalogue.
- `lib/xinyu/media-allowlist.json`: original public video ID, canonical Bilibili
  reference, CID and free-video flag only; no local files or user state.
- `lib/xinyu/media.mjs`: exact copy of the reviewed web media implementation.
- `lib/xinyu/site-handler.mjs`: raw static responses and request-local API auth.

All generated HTTP responses use `private, no-store`. The existing SW can
explicitly retain its fixed public application/textbook assets in Cache Storage;
it validates status, redirect, MIME and app/catalogue markers before storing.
The adapter does not cache API traffic, identity, or auth errors. An already
cached public shell/catalogue may work offline; private user state remains local
in the browser and video access is reauthorized server-side.

Owner-only membership is enforced by the confirmed owner-private Sites access
policy, not by any arbitrary ID or custom header in application code. Do not run
this code as a public Site without separately reviewing authorization. The
official helper trusts only Sites dispatch's identity contract.

Tests (no install, network or publication):

```powershell
node --test web/deploy/tests/sites.test.mjs
```

After generation the main task still must run the official Sites build helper,
check the generated route under Vinext/Workers, inspect the final source package
for extraneous files, and check owner login, anonymous login/asset rejection,
video discovery and Range streaming in the actual private environment. Local
unit tests do not establish hosted authentication or origin playback success.
