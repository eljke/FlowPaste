# FlowPaste — native SwiftUI for LiveContainer

Native text tools with explicit local history and JSON backup restore. Device IPA builds and simulator launch checks run in GitHub Actions; LiveContainer behaviour requires a real iPhone test.

Make pasted content instantly useful. User-initiated clipboard read, safe URL cleanup, formatting (JSON/Base64/lines), QR, explicit local history and fast retrieval. **Never** promise background recording of other apps clipboard.

## Implemented

Receive content from another app with **Share → LiveContainer → FlowPaste** (LiveContainer 3.8+ with its ShareExtension installed). Web links and UTF-8 text/JSON files open directly in the workbench; no separate clipboard paste is required. Both URL-open events and web-browsing user activities are handled, including launches from a stopped app. An existing draft requires confirmation before replacement; incoming data is never automatically saved to history or fetched from the network.

LiveContainer's share extension forwards URLs and files. Selection of plain text without a URL/file depends on the host extension and is not provided by this guest IPA. FlowPaste does not register its own system share extension while running as a guest. See the [LiveContainer 3.8 release notes](https://github.com/LiveContainer/LiveContainer/releases/tag/3.8.0).

Native SwiftUI workbench, explicit paste, content-aware action suggestions, URL tracker cleanup with preserved query encoding, pretty/minified JSON without changing numeric precision or key order, sort/dedupe/trim (including Windows line endings), upper/lower and UTF-8 Base64. Results can be copied, shared or reused as input.

Local SQLite history supports Cyrillic case-insensitive literal search, pinned items, record details, reopening in the workbench and undo of the most recent deletion. JSON backup exports the complete history and restores missing records atomically after a preview. Existing records are preserved; repeated restores do not duplicate them. Backups from 0.1.0 remain compatible.

QR codes are generated locally on a white background and can be shared as images. All three tabs show operation feedback and storage errors. Text processing runs away from the UI thread, and editing input discards stale results.

## Known gaps

History is user-saved, not system-wide. Redirect resolution and QR scanning are not implemented. LiveContainer routing, clipboard permissions, file sharing and import require device testing; simulator tests verify receiving URLs at the app boundary without running LiveContainer.

Input and saved records are limited to 1 MiB of UTF-8 text. Pretty JSON results are capped at 4 MiB. Backups are limited to 20 MiB and 10,000 records; an oversized export reports an error instead of silently dropping records. History displays the first 500 matches; refine search to find older entries. Long text previews display the first 12,000 characters while copy/share use the full text. QR payloads are limited to 1,800 UTF-8 bytes for reliable scanning.

## Windows 11 Quick Start

1. Follow [WINDOWS11_BUILD.md](WINDOWS11_BUILD.md). Install Git and GitHub CLI, authenticate, set Git author name/email.
2. Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\publish_windows.ps1` from the unpacked project root.
3. In GitHub Actions select **Build IPA** → **Run workflow**. Download the artifact and unpack the unsigned `.ipa`.
4. Import/sign under your LiveContainer setup; verify app launch and features on the device.

## Developer operations

- Portable unit tests: `swift test` on supported Swift environment (GitHub CI validates).
- Release and IPA verifier tests: `python tools/test_release.py` and `python tools/test_ipa.py`.
- Simulator UI test (transform, save, reopen, delete/undo, relaunch) and screenshot: `bash tools/smoke_simulator.sh` on macOS with Xcode.
- Regenerate Xcode: `python tools/generate_xcodeproj.py` (checked into Git).
- Deterministic SemVer planner: `python tools/release.py plan` (requires Git history).
- Release on `master`: Conventional Commit changes cause GitHub Actions to create `release/vX.Y.Z`, compile IPA, publish GitHub Release, then merge branch back to master when allowed.
- Master prompt: [MASTER_PROMPT.md](MASTER_PROMPT.md). Agent instructions: [AGENTS.md](AGENTS.md). Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Current constraints

- System clipboard/audio cannot be intercepted across other apps; LiveContainer does not grant extra privileges.
- The artifact is **unsigned**; a compiled IPA is not proof of successful import/run in LiveContainer.
- Developer cannot run Xcode locally on Windows; the Xcode 27 GitHub runner performs compilation.
- Automated branch merge works in non-protected `master`. If protection denies direct pushes, release branch and PR remain for authorized merge (see Windows doc).

Copyright and app identifiers are placeholders; change `Config/project.json` bundle ID before public distribution.
