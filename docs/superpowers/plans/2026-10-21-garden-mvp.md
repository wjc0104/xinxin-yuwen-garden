# Xinxin Garden Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a private repository and a native iOS 15 TrollStore IPA for 欣欣的语文小花园.
**Architecture:** One SwiftUI application, a dependency-free Foundation domain library, atomic local JSON persistence, and a tightly scoped EventKit adapter. Catalog/source metadata ship with the app; external searches open their real platform; calendar writes are explicit.
**Tech Stack:** Swift 5, SwiftUI, Foundation, WebKit, PDFKit, AVKit, SafariServices, EventKit, XcodeGen, GitHub macOS Actions.
**Spec:** docs/superpowers/specs/2026-10-21-garden-design.md

## Global Constraints
- iOS 15.0 minimum, arm64, IPA for TrollStore.
- No invented catalog verification, exam-frequency claims, videos or API results.
- 16 only uses the system calendar. Calendar permission is requested after an explicit action; only the newly created dedicated calendar may be modified.
- Keep the verified 16 weekly periods and the 15-minute intermissions in the two Thursday composition groups.
- Private data stays local; imported backups exclude calendar bindings; free resources first.

## Review Focus
- A moved/cancelled occurrence must not leave the old reminder or rewrite following weeks.
- Calendar ownership checks must prevent editing other calendars or user-added events, including after backup restore.
- Denied/revoked access and deleted calendar must surface an error, not pretend sync succeeded.
- Malformed backups or paths must not destroy existing notes or read arbitrary local files.
- iOS 16/17-only SwiftUI APIs must not enter the iOS 15 target; imported files and Chinese search must work.

---

### Task 1: Domain, curriculum and real tests

**Files:** Package.swift; Sources/GardenCore/{Models,ScheduleEngine,SearchEngine,DiskStore}.swift; Tests/GardenCoreTests; App/Resources/catalog.json.
**Interfaces:** GardenSnapshot stores resources, highlights and schedule changes; ScheduleEngine generates Occurrence values identified by original slot/date; SearchEngine produces local matches and validated HTTP(S) source URLs; DiskStore saves and merges snapshots atomically.
- [ ] Write domain tests with hand-derived Monday/Thursday fixtures, cancellation/move, permanent effective date, URL encoding, blank and unsafe URLs, malformed backup and persistence checks.
- [ ] Run `swift test` in macOS Actions against compileable placeholder implementations; Expected: XCTest assertion failures for unimplemented behavior.
- [ ] Implement the real Foundation behavior and catalog loader; preserve verified metadata and explicit pending labels.
- [ ] Run `swift test`; Expected: all tests pass. Commit domain and data.

### Task 2: Native app, annotations and calendar adapter

**Files:** App/{XinxinGardenApp,AppStore,Theme,CatalogViews,ReadingViews,SearchViews,NotesViews,ScheduleViews,SettingsViews,CalendarBridge,FileImport}.swift; project.yml; UI tests.
**Interfaces:** The UI uses the Task 1 models directly. CalendarBridge projects ScheduleEngine occurrences and stores device-local ownership links separately from backup data.
- [ ] Add meaningful persistence, schedule projection and UI smoke tests before the views they exercise.
- [ ] Implement five native tabs, real local search, platform search links, notes, highlights, PDF/video file import and bookmarks, and schedule editing.
- [ ] Implement explicit calendar permissions, account selection, owned calendar creation, idempotent event updates, external change review, and clean failure messages.
- [ ] Run `swift test` and `xcodebuild test` on an available iPhone simulator; Expected: green tests plus screenshots of main pages.
- [ ] Commit the app and adapter.

### Task 3: Cute documentation, icon, review and IPA

**Files:** README.md; docs/PRIVACY.md; docs/INSTALL.md; .github/workflows/build-ipa.yml; scripts/package-ipa.sh; App/Assets.xcassets.
**Interfaces:** Workflow consumes project.yml and app sources; produces XinxinGarden.ipa, checksums, and simulator screenshots; no signing account or secret.
- [ ] Create original vector-style flower/book icon and affectionate Chinese README with truthful first-version limits and sources.
- [ ] Build for generic iOS device with code signing disabled, ad-hoc sign executable, package Payload/XinxinGarden.app as IPA; verify arm64 and MinimumOSVersion 15.0.
- [ ] Run one fresh whole-repository reviewer, address material findings with reproducing tests, and rerun the suite/build.
- [ ] Download the exact successful build to outputs/, inspect IPA archive and checksum, publish a v0.0.1 release in the private repository. Expected: repository and downloadable IPA, with physical device testing still explicitly pending. User selected the short app name 欣语.
