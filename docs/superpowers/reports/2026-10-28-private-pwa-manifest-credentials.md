# Private PWA manifest credentials fix

Delivery target: mobile web/PWA, not IPA. Existing source baseline a33a92d2a215e819f55a34970d13a84b717c1e78.

The existing private Sites handler authenticates every static resource, including the manifest. Add crossorigin="use-credentials" to the existing same-origin manifest link; do not expose the manifest anonymously or change the Site audience. A single assertion in the existing deployment test ensures generated HTML retains this attribute. Re-export the existing public catalogue/assets to update the service-worker version from44b5fe18cc9833b5 to90f85975bec8fea1; catalogue bytes and198 lessons/1163resources remain unchanged.

Independent read-only review found no P1/P2 and confirmed precisely one HTML line plus one test assertion; exporter does not overwrite index.html. Existing staged RED on original HTML and GREEN on candidate recorded. Root applied exact reviewed SHA after recoverable backup and reran actual repository tests:45 Web/deploy tests passed, zero skips;4 existing CI logic tests passed. git diff--check passed. These are source/logic results, not hosted login, manifest fetch, Safari home-screen installation, real playback or carrier proof.

References: https://web.dev/articles/add-manifest and https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Manifest . Credentialed manifest fetching is required even on the same origin.

Not deployed. The previously deployed private Site is not accessible from the current connected account; last inventory showed an older owner-private unpublished Site instead. The user rejected the old default-domain URL for direct/proxy access. No new third Site, anonymous upload, audience change, fee or account enrollment was attempted. A hosting-login/resource choice was requested; no answer received at this checkpoint. No success email, no shutdown, no further native workflow. Keep the existing private-access requirement until the user explicitly changes it.
