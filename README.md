# FlowPaste — native SwiftUI for LiveContainer

**Status: 0.1.0 source MVP; arm64 IPA build configured but not verified on GitHub or iPhone.**

Make pasted content instantly useful. User-initiated clipboard read, safe URL cleanup, formatting (JSON/Base64/lines), QR, explicit local history and fast retrieval. **Never** promise background recording of other apps clipboard.

## Implemented

Native SwiftUI workbench, explicit paste, URL tracker cleanup, pretty/minified JSON, sort/dedupe/trim, upper/lower, Base64, local SQLite clip history, pinned items, query, QR, JSON export. No background capture, no system keyboard or share extension.

## Known gaps

History is user-saved, not system-wide. No import restore yet. Many URL redirects/tracker patterns and QR scan are not implemented. Pasteboard permissions in guest IPA not device-tested.

## Windows 11 Quick Start

1. Follow [WINDOWS11_BUILD.md](WINDOWS11_BUILD.md). Install Git and GitHub CLI, authenticate, set Git author name/email.
2. Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\publish_windows.ps1` from the unpacked project root.
3. In GitHub Actions select **Build IPA** → **Run workflow**. Download the artifact and unpack the unsigned `.ipa`.
4. Import/sign under your LiveContainer setup; verify app launch and features on the device.

## Developer operations

- Portable unit tests: `swift test` on supported Swift environment (GitHub CI validates).
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
