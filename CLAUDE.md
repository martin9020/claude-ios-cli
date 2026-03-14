# ClaudeShell Development Guide

## What This Project Is

An iOS app that provides a terminal/shell experience on iPhone with Claude Code built in.
Open the app, get a shell prompt, run commands and talk to Claude — just like on a PC.

## Development Workflow

### Step 1: Edit Code

Source locations:
- **Shell engine (C):** `ClaudeShell/Shell/` and `ClaudeShell/Commands/`
- **iOS app (Swift):** `ClaudeShell/App/`, `ClaudeShell/Claude/`, `ClaudeShell/Terminal/`
- **Node/npm (Swift):** `ClaudeShell/Node/`
- **Bridge (Swift-C):** `ClaudeShell/Bridge/`
- **CI config:** `.github/workflows/`

### Step 2: Test Locally (Windows)

```bash
cd ClaudeShell/Shell
gcc -o shell_test.exe test_main.c shell.c shell_helpers.c environment.c \
    ../Commands/cmd_system.c ../Commands/cmd_filesystem.c \
    ../Commands/cmd_text.c ../Commands/cmd_network.c \
    -DTEST_MODE -I.
./shell_test.exe
```

Expected: `22 passed, 0 failed` (or more as tests are added).

### Step 3: Push & Build

```bash
git add -A && git commit -m "description" && git push origin master
```

CI builds in ~40s (cached xcodegen, single device build, -quiet).

### Step 4: Download IPA

```bash
gh run download <run-id> --name ClaudeShell-sideload --dir Desktop
```

Install via AltStore or Sideloadly.

---

## Feature Status

### Shell Engine (C) — WORKING
- [x] Command tokenizer with quote handling
- [x] Environment variable expansion ($VAR, ${VAR})
- [x] && and || operators
- [x] Exit code tracking ($?)
- [x] Comments (#)
- [x] Variable assignment (VAR=value, export)
- [x] Pipe support (cmd1 | cmd2)
- [x] Output redirection (cmd > file, cmd >> file)

### Built-in Commands — WORKING
- [x] Filesystem: ls, cat, cp, mv, rm, mkdir, touch, pwd, cd, find, chmod, du, ln
- [x] Text: grep, head, tail, wc, sort, uniq, sed, tr, cut, diff
- [x] System: echo, env, which, clear, exit, help, date, sleep, test, basename, dirname
- [x] Network: curl, wget (via URLSession bridge)
- [x] Node.js: node (JavaScriptCore), npm install/list/run
- [x] Claude: interactive mode, one-shot, config, status

### iOS App (Swift) — WORKING
- [x] Terminal emulator with scrollback
- [x] ANSI escape code handling
- [x] Command history (up/down arrows)
- [x] Quick-command bar (context-dependent: shell vs claude mode)
- [x] Dark theme terminal UI
- [x] Settings: OAuth sign-in, API key, model picker, font size
- [x] Text selection on terminal output

### Authentication — WORKING
- [x] OAuth PKCE flow (Pro/Max subscription, no API key needed)
- [x] Hardcoded client_id from Claude Code source
- [x] Manual code entry flow (browser → copy code → paste in app)
- [x] OAuth token → API key exchange via create_api_key endpoint
- [x] Keychain storage for tokens
- [x] Token refresh on expiry
- [x] API key fallback (manual entry in Settings)
- [x] Cached browser sessions (auto-login if already signed in)

### Claude AI — WORKING
- [x] Interactive mode (`claude` command)
- [x] One-shot mode (`claude <message>`)
- [x] Autonomous tool use: bash, read_file, write_file
- [x] Agentic loop (up to 25 iterations)
- [x] Multi-turn conversation history
- [x] File context auto-loading
- [x] Live tool progress display
- [x] Dynamic model selection from Settings
- [x] Sandbox path validation (prevents ../ escape)

### Build & Deploy — WORKING
- [x] GitHub Actions CI (~40s builds, cached xcodegen)
- [x] Xcode project generation (xcodegen)
- [x] Device build (Release ARM64)
- [x] IPA packaging and artifact upload
- [x] Local C engine testing (22 tests, Windows cross-compile)
- [x] Zero compiler warnings (-Wall -Wextra)

### Future / TODO
- [ ] Input redirection (cmd < file)
- [ ] Here documents (<<EOF)
- [ ] Glob expansion (*.txt)
- [ ] Streaming responses (show tokens as they arrive)
- [ ] Tab completion
- [ ] Keyboard shortcuts (Ctrl+C, Ctrl+D)

---

## Key Technical Decisions

### Why C for the shell engine?
Compiles to ARM64 natively, no runtime deps, testable on any platform.
Swift calls C through the bridging header.

### Why OpaquePointer workaround?
Swift can't access C structs with fixed-size pointer arrays.
`shell_helpers.c` provides accessor functions.

### Why URLSession for networking?
iOS sandbox blocks raw sockets. curl/wget bridge to Swift URLSession.

### OAuth flow (matches Claude Code CLI)
1. Open `platform.claude.com/oauth/authorize` with PKCE
2. User authorizes → gets code on screen
3. User pastes code back into app
4. Exchange code for OAuth token (JSON POST)
5. Exchange OAuth token for API key via `create_api_key` endpoint
6. Use API key with `x-api-key` header for all Claude API calls

### Sandbox constraints
- All files confined to app's Documents directory
- Shell `/` maps to Documents/ — no escape
- Network requires NSAllowsArbitraryLoads

---

## File Ownership

| File | Purpose | When to modify |
|------|---------|----------------|
| `shell.c` | Core interpreter, pipes, redirects | Shell syntax features |
| `cmd_system.c` | System commands + dispatch table | ANY new command |
| `cmd_filesystem.c` | File operations | File commands |
| `cmd_text.c` | Text processing | Text commands |
| `cmd_network.c` | Network (curl/wget) | Network commands |
| `shell_helpers.c` | Swift-safe struct accessors | When Shell struct changes |
| `ShellBridge.swift` | C-to-Swift bridge, tool execution | C API or tool changes |
| `ClaudeEngine.swift` | Anthropic API client | API/model changes |
| `OAuthManager.swift` | OAuth PKCE + API key creation | Auth changes |
| `TerminalView.swift` | Main UI | UI changes |
| `SettingsView.swift` | Settings screen | Settings UI changes |
| `NpmManager.swift` | npm package manager | npm features |
| `JsEngine.swift` | JavaScriptCore runtime | JS engine changes |
| `ToolDefinitions.swift` | Claude tool schemas | Adding tools |
| `test_main.c` | Local test harness | Adding any command |
| `build-ios.yml` | CI pipeline | Build/deploy changes |
