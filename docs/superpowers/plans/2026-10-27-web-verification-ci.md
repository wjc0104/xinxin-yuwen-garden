# Web verification workflow

> **For agentic workers:** Use subagent-driven-development for scoped implementation and review.

Goal: unattended web tests with explicit PASS/FAIL/NOT CHECKED reporting, not a false claim of mobile-network acceptance.
Spec: current user wants the girlfriend's phone to work without a computer on Wi-Fi/mobile, with/without proxy. She need not monitor this chat. Primary five-hour remaining<=5% saves/pauses/keepsPC on; resets resumes. Only complete verified delivery+successful Gmail large-account message permits root shutdown.

## Scope and constraints
- Preserve native Swift, IPA workflow gates, existing public source boundaries and private audience.
- Existing web 45 tests pass; Sites private URL is not reachable on user's networks, explicitly NOT accepted.
- Do not embed provider video UI, hardcode a success fixture as real playback, weaken gates, add paid services, publish public data or log tokens/upstream media locators.
- Hosted HTTP green is not China carrier or physical Safari proof. Four independent manual-network conditions must remain UNKNOWN until measured; CI must not mark complete when they are unknown.

## Task 1: bounded CI with evidence
Files: .github/workflows/web-tests.yml, web/ci/ verification scripts/tests/docs and web README if needed. No product changes, no other workflow modifications.
- Run all existing web Node and deployment adapter tests and regenerate public asset export on Linux.
- Add automated browser checks of the built app using a loopback fixture server only, no production auth bypass: navigation, exact 春/毛泽东 search, note save/reload, transcript selection if feasible, system-video controls/real decoded frames from an authored generated local media fixture, speed/current-time notes. Fixture evidence explicitly synthetic/local and never counted as deployed original-video playback.
- Use official browser automation toolchain as dev-only CI dependency, reproducible version lock. User explicitly asked CI autonomous tests, no need interact with user's browser for CI. Dependencies not added to product.
- Remote optional target comes only from explicit workflow_dispatch URL or trusted repo variable. Validate HTTPS/no credentials/no custom ports/localhost/private IPs; public known expected hostname allowlist or exact configured host. Do not accept arbitrary proxy URLs. Redirect/auth/cloud challenge/failure must not count as pass; sanitized structured report stores statuses, no cookies/secrets/HTML bodies signed locators.
- Distinguish code_suite/browser_fixture/hosted_access/hosted_real_playback/network_matrix. Remote unknown cannot be global completion. No secrets configured is NOT CHECKED, not success. For explicit remote verification requested, unreadable/unverified target must fail the acceptance job while independent offline tests still run.
- Save small JSON report, screenshots/localtrace with bounded retention; use no sensitive webpage traces. Human job summary concise Chinese states what is proven, failed and not measured. No CI email success or shutdown trigger.
- Run meaningful script/unit/yaml checks locally, test refusal/auth/challenge/timeout/notchecked conditions RED→GREEN. Root runs gh workflow on exact pushed feature head; never push/main/deploy as agent.
- Finish scoped report docs/superpowers/reports/2026-10-27-web-verification-ci.md, no fake completed status.

## Task 2 controller
- Review exact changes independently, fix important issues then local commit with approval.
- Verify GitHub account wjc0104/repo/remote and dispatch exact feature head; record status/artifacts.
- If CI/hosting does not establish all acceptance, continue work or checkpoint with unmet items; no success email, no shutdown. Network matrices need actual user routes or suitable measured direct probes, never fabricated.
