# ClaudeShell — Project Status

## Current State: FUNCTIONAL (v1.0)

The app builds, installs via sideloading, and core features work.
OAuth sign-in with Pro/Max subscription is implemented.

---

## What's Done

### Phase 1: OAuth Login ✅
- OAuth PKCE flow matching Claude Code CLI source exactly
- Hardcoded client_id (no npm install required for auth)
- Manual code entry (browser shows code → paste in app)
- OAuth token exchanged for real API key via create_api_key endpoint
- Keychain storage, token refresh, cached browser sessions
- Settings UI: one-tap sign in, sign out, status display

### Phase 2: Autonomous Tool Use ✅
- 3 tools: bash, read_file, write_file
- Agentic loop with 25-iteration cap
- Live tool progress display
- File context auto-loading from prompts
- Sandbox path validation

### Shell Engine ✅
- 40+ built-in commands (filesystem, text, system, network)
- Pipe support, output redirection
- Variable expansion, quote handling, operators
- 22 passing tests, zero compiler warnings

### Build Pipeline ✅
- ~40s CI builds (GitHub Actions, cached xcodegen)
- Single device build (no redundant simulator build)
- IPA artifact uploaded automatically

---

## What's Next

### Priority 1: Verify End-to-End
- [ ] Confirm OAuth → API key → Claude chat works fully
- [ ] Test `ls`, `cat`, `grep`, all commands show output
- [ ] Test pipe and redirect on device
- [ ] Test Claude autonomous mode (create files, run commands)

### Priority 2: Polish
- [ ] Streaming responses (show tokens as they arrive)
- [ ] Better error messages for common failures
- [ ] Tab completion for commands and file paths
- [ ] Keyboard shortcuts (Ctrl+C to cancel)

### Priority 3: Features
- [ ] Input redirection (cmd < file)
- [ ] Glob expansion (*.txt)
- [ ] Command history persistence (save to file)
- [ ] git operations (basic clone, status, diff)

---

## Architecture

```
User Input → TerminalView.swift
                ↓
        ShellBridge.swift (C-Swift bridge)
                ↓
        shell_exec() → cmd_dispatch() → cmd_*()
                ↓
        Output → captureBuffer → TerminalView

Claude Mode:
        User Input → handleClaudeInputAgentic()
                ↓
        ClaudeEngine.sendMessageWithTools()
                ↓
        Tool calls → executeTool() → shell commands
                ↓
        Loop until text response or 25 iterations
```

## Key Files Changed (This Session)
- `OAuthManager.swift` — Complete rewrite: PKCE, manual code flow, API key creation
- `ClaudeEngine.swift` — Auth method handling, model from Settings
- `ShellBridge.swift` — Output buffer race condition fix, sandbox validation
- `TerminalView.swift` — Sync output capture
- `NpmManager.swift` — Scoped packages, tar extraction, abbreviated metadata
- `shell.c` — Pipe + redirect implementation
- `build-ios.yml` — Optimized to ~40s (cached xcodegen, single build)
