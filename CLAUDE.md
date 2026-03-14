# ClaudeShell Development Guide

## What This Project Is

An iOS app that provides a terminal/shell experience on iPhone with Claude Code built in.
Open the app, get a shell prompt, run commands and talk to Claude — just like on a PC.

## Development Workflow

### Step 1: Edit Code

- **Shell engine (C):** `ClaudeShell/Shell/` and `ClaudeShell/Commands/`
- **iOS app (Swift):** `ClaudeShell/App/`, `ClaudeShell/Claude/`, `ClaudeShell/Terminal/`
- **Node/npm (Swift):** `ClaudeShell/Node/`
- **Bridge (Swift-C):** `ClaudeShell/Bridge/`
- **CI config:** `.github/workflows/`

### Step 2: Test Locally (Windows)

```bash
export PATH="/c/msys64/mingw64/bin:$PATH"
cd ClaudeShell/Shell
gcc -o shell_test.exe test_main.c shell.c shell_helpers.c environment.c \
    ../Commands/cmd_system.c ../Commands/cmd_filesystem.c \
    ../Commands/cmd_text.c ../Commands/cmd_network.c \
    -DTEST_MODE -I. -Wall -Wextra -Wno-unused-parameter
./shell_test.exe
```

Expected: `22 passed, 0 failed`

### Step 3: Push & Build (~40s)

```bash
git add -A && git commit -m "description" && git push origin master
```

### Step 4: Download IPA

```bash
RUN_ID=$(gh run list --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch $RUN_ID --exit-status
rm -f Desktop/ClaudeShell-sideload.ipa
gh run download $RUN_ID --name ClaudeShell-sideload --dir Desktop
```

### Step 5: QA Test on Device

See `QA-TEST.md` for comprehensive test instructions. Enter `claude` mode on the device and ask Claude to run the full test suite.

---

## Feature Status

### Shell Engine (C) — WORKING ✅
- [x] Command tokenizer with quote handling
- [x] Environment variable expansion ($VAR, ${VAR})
- [x] && and || operators
- [x] Exit code tracking ($?)
- [x] Comments (#)
- [x] Variable assignment (VAR=value, export)
- [x] Pipe support (cmd1 | cmd2)
- [x] Output redirection (cmd > file, cmd >> file)

### Built-in Commands (40+) — WORKING ✅
- [x] **Filesystem:** ls, cat, cp, mv, rm, mkdir, touch, pwd, cd, find, chmod, du, ln
- [x] **Text:** grep, head, tail, wc, sort, uniq, sed, tr, cut, diff
- [x] **System:** echo, env, which, clear, exit, help, date, sleep, test, basename, dirname
- [x] **Network:** curl, wget (via URLSession bridge)
- [x] **Node.js:** node (JavaScriptCore), npm install/list/run
- [x] **Claude:** interactive mode, one-shot, config, status

### iOS App (Swift) — WORKING ✅
- [x] Terminal emulator with scrollback (5000 lines)
- [x] ANSI escape code handling
- [x] Command history (up/down arrows)
- [x] Quick-command bar (context-dependent: shell vs claude mode)
- [x] Copy button (copies full terminal log to clipboard)
- [x] Dark theme terminal UI
- [x] Settings: OAuth sign-in, API key, model picker, font size
- [x] Text selection on terminal output

### Authentication — WORKING ✅
- [x] OAuth PKCE flow via claude.ai (Pro/Max subscription)
- [x] Manual code entry (browser → copy code → paste in app → strips # fragment)
- [x] Bearer token with `anthropic-beta: oauth-2025-04-20` header
- [x] Keychain storage for tokens
- [x] Token refresh on expiry
- [x] API key fallback (manual entry in Settings)
- [x] Cached browser sessions (auto-login)

### Claude AI — WORKING ✅
- [x] Interactive mode (`claude` command)
- [x] One-shot mode (`claude <message>`)
- [x] Autonomous tool use: bash, read_file, write_file
- [x] Agentic loop (up to 25 iterations)
- [x] Orphaned tool_use fix (adds tool_result on max iterations)
- [x] Multi-turn conversation history (20 messages)
- [x] File context auto-loading
- [x] Live tool progress display (orange ⚙ indicators)
- [x] Dynamic model selection from Settings
- [x] Sandbox path validation (prevents ../ escape)

### Build & Deploy — WORKING ✅
- [x] GitHub Actions CI (~40s builds, cached xcodegen)
- [x] Single device build (Release ARM64, -quiet flag)
- [x] IPA packaging and artifact upload
- [x] 22 local C tests, zero compiler warnings

---

## Architecture

```
User Input → TerminalView.swift
                ↓
        ShellBridge.swift (C↔Swift bridge)
                ↓
        shell_exec() → cmd_dispatch() → cmd_*()
                ↓
        captureBuffer (synchronous) → TerminalView

Claude Mode:
        User Input → handleClaudeInputAgentic()
                ↓
        ClaudeEngine.sendMessageWithTools()
          ↓ (Authorization: Bearer for OAuth, x-api-key for API keys)
          ↓ (anthropic-beta: oauth-2025-04-20)
          ↓ (anthropic-version: 2023-06-01)
                ↓
        Tool calls → executeTool() → shell commands
                ↓
        Loop until text response or 25 iterations
```

## OAuth Flow (matches Claude Code CLI)

1. Open `claude.ai/oauth/authorize` with PKCE + `code=true`
2. User authorizes → page shows code with `#fragment`
3. User copies code → app strips `#fragment` → pastes in Settings
4. Exchange code for OAuth token (JSON POST to `platform.claude.com/v1/oauth/token`)
5. Store token in Keychain
6. API calls use `Authorization: Bearer {token}` + `anthropic-beta: oauth-2025-04-20`

## Key Values (from Claude Code npm source)

| Constant | Value |
|----------|-------|
| client_id | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` |
| authorize | `https://claude.ai/oauth/authorize` |
| token | `https://platform.claude.com/v1/oauth/token` |
| redirect | `https://platform.claude.com/oauth/code/callback` |
| api_version | `2023-06-01` |
| beta | `oauth-2025-04-20` |

---

## File Ownership

| File | Purpose |
|------|---------|
| `shell.c` | Core interpreter, pipes, redirects |
| `cmd_system.c` | System commands + dispatch table |
| `cmd_filesystem.c` | File operations |
| `cmd_text.c` | Text processing |
| `cmd_network.c` | Network (curl/wget) |
| `shell_helpers.c` | Swift-safe struct accessors |
| `ShellBridge.swift` | C↔Swift bridge, tool execution, agentic loop |
| `ClaudeEngine.swift` | Anthropic API client, auth handling |
| `OAuthManager.swift` | OAuth PKCE flow |
| `TerminalView.swift` | Main UI, command execution |
| `SettingsView.swift` | Settings screen |
| `TerminalEmulator.swift` | Output buffer, scrollback, ANSI |
| `NpmManager.swift` | npm package manager |
| `JsEngine.swift` | JavaScriptCore runtime |
| `ToolDefinitions.swift` | Claude tool schemas |
| `test_main.c` | 22 local tests |
| `build-ios.yml` | CI pipeline (~40s) |

---

## TODO (Future)

- [ ] Input redirection (cmd < file)
- [ ] Here documents (<<EOF)
- [ ] Glob expansion (*.txt)
- [ ] Streaming responses (show tokens as they arrive)
- [ ] Tab completion
- [ ] Keyboard shortcuts (Ctrl+C, Ctrl+D)
- [ ] Session resume (persist conversation across app restarts)
- [ ] Increase iteration cap or make configurable
