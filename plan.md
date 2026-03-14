# ClaudeShell — Project Status

**Last updated:** 2026-03-14

## Current State: STABLE v1.1 ✅

Full QA: 64/70 pass (91.4%), 0 hard failures, 6 minor quirks.
All core features working and verified on device.

---

## Verified Working ✅

- **OAuth** — Pro/Max login via claude.ai, Bearer + oauth beta header
- **Dual Tabs** — Shell (green) + Claude (purple), independent output
- **40+ Commands** — filesystem, text, system, network, node/npm
- **Claude AI** — autonomous tool use, 75 iteration cap, background task for screen lock
- **Copy Button** — copies active tab's log to clipboard
- **Files App** — browse sandbox files in iOS Files
- **CI** — ~40s builds, cached xcodegen

## Known Quirks (not bugs)

- `sort` needs file arg (doesn't read stdin directly — pipe handles it via temp file)
- `/dev/null` and `2>&1` not available (iOS sandbox)
- Shell redirects (`>`, `>>`) session-scoped — use `write_file` for persistence
- `VAR=val cmd` inline prefix syntax not supported
