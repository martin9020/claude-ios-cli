# ClaudeShell — Project Status

**Last updated:** 2026-03-14

## Current State: WORKING v1.0 ✅

OAuth login with Pro/Max subscription works. Claude AI responds.
Shell commands work. Tool use works. Copy button works.

---

## Completed ✅

### OAuth Authentication
- PKCE flow via claude.ai (not platform.claude.com)
- Manual code entry with #fragment stripping
- Bearer token + `anthropic-beta: oauth-2025-04-20` header
- Token refresh, Keychain storage, cached sessions
- API key fallback for manual entry

### Shell Engine
- 40+ built-in commands (filesystem, text, system, network)
- Pipes, output redirection, variable expansion
- 22 passing tests, zero warnings

### Claude AI Integration
- Interactive + one-shot modes
- Autonomous tool use (bash, read_file, write_file)
- 25-iteration agentic loop with orphaned tool_use fix
- File context auto-loading, sandbox path validation

### iOS App
- Terminal UI with scrollback, command history
- Copy button for terminal log
- Settings: OAuth sign-in, API key, model picker
- Quick command bars (context-dependent)

### Build Pipeline
- ~40s CI builds (cached xcodegen, single device build)
- Auto IPA packaging and artifact upload

---

## Known Issues 🐛

- [ ] /dev/null redirection doesn't work
- [ ] `help <command>` doesn't give per-command details
- [ ] Piping has edge cases with some commands
- [ ] 25 iteration limit can be hit on large tasks
- [ ] No session persistence (conversation lost on /exit or app close)

---

## Next Up 📋

### Priority 1: QA & Stability
- [ ] Run full QA test suite (see QA-TEST.md)
- [ ] Fix any failures found in QA
- [ ] Test all commands show correct output

### Priority 2: UX Polish
- [ ] Streaming responses (tokens as they arrive)
- [ ] Session resume (persist conversation)
- [ ] Configurable iteration limit
- [ ] Better error messages

### Priority 3: New Features
- [ ] Input redirection (cmd < file)
- [ ] Glob expansion (*.txt)
- [ ] Tab completion
- [ ] Keyboard shortcuts (Ctrl+C)
- [ ] Command history persistence

---

## Session Log (2026-03-14)

Major changes made today:
1. Full code review + bug fixes (crash fixes, security, race conditions)
2. Implemented pipe support and output redirection
3. Implemented OAuth PKCE flow (matching Claude Code CLI source)
4. Fixed output buffer race condition (commands showing no output)
5. Added `anthropic-beta: oauth-2025-04-20` header for Bearer auth
6. Fixed orphaned tool_use blocks on max iterations
7. Added copy button for terminal log
8. Optimized CI from 2.5min to ~40s
9. 22 C engine tests, zero compiler warnings
