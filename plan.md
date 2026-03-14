# ClaudeShell — Project Status

**Version:** 1.1 | **QA:** 64/70 (91.4%) | **Build:** ~40s | **Date:** 2026-03-14

## Status: STABLE ✅

All core features working and verified on device.

## What's In

- OAuth Pro/Max via claude.ai
- Dual tabs (Shell + Claude)
- 40+ shell commands with pipes, redirects, variables
- Claude autonomous tools (bash, read_file, write_file)
- 75 iteration cap, background task for screen lock
- Copy button, Files app access, npm/node
- echo -e, du -h, tail -N, uniq -c, cut -d, tr -d/-s
- Single quotes prevent $VAR expansion

## Known Quirks

- `sort` needs file arg (pipe handles via temp file)
- `/dev/null` and `2>&1` not available
- Shell redirects session-scoped (use write_file for persistence)
