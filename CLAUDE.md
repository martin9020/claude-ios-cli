# ClaudeShell Development Guide

## What This Project Is

An iOS app that provides a `cmd.exe`/terminal experience on iPhone with Claude Code built in.
The end goal: open the app, get a shell prompt, run commands and talk to Claude just like on a PC.

## Development Workflow

Every change should follow this pipeline. Do NOT skip steps.

### Step 1: Edit Code

Source locations:
- **Shell engine (C):** `ClaudeShell/Shell/` and `ClaudeShell/Commands/`
- **iOS app (Swift):** `ClaudeShell/App/`, `ClaudeShell/Claude/`, `ClaudeShell/Terminal/`
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

If adding new commands, add matching tests in `test_main.c`.

### Step 3: Push to GitHub

```bash
git add -A
git commit -m "description of change"
git push origin master
```

This auto-triggers the CI pipeline.

### Step 4: CI Pipeline (GitHub Actions)

The `build-ios.yml` workflow runs automatically on push:

```
[1] Install xcodegen           ~30s
[2] Generate Xcode project     ~5s
[3] Select Xcode               ~2s
[4] Build for Simulator        ~30s   <-- catches Swift compile errors
[5] Run iOS Tests              ~30s   <-- catches runtime bugs
[6] Build for Device (Release) ~30s   <-- real ARM64 binary
[7] Validate .app bundle       ~5s    <-- checks Info.plist, binary, arch
[8] Package IPA                ~5s    <-- creates sideloadable .ipa
[9] Upload artifact            ~5s    <-- downloadable from Actions tab
```

If ANY step fails, the SSH debug session activates (free, on the same runner).

### Step 5: Download & Install IPA

```bash
gh run download <run-id> --name ClaudeShell-sideload --dir Desktop
```

Then install via AltStore or Sideloadly on iPhone.

---

## Checklist: What Needs to Work

### Shell Engine (C)
- [x] Command tokenizer with quote handling
- [x] Environment variable expansion ($VAR, ${VAR})
- [x] && and || operators
- [x] Exit code tracking ($?)
- [x] Comments (#)
- [x] Variable assignment (VAR=value, export)
- [x] Pipe support (cmd1 | cmd2) — captures left output, feeds to right via temp file
- [ ] Input redirection (cmd < file)
- [x] Output redirection (cmd > file, cmd >> file) — captures and writes to file
- [ ] Here documents (<<EOF)
- [ ] Glob expansion (*.txt)
- [ ] Command history persistence (save to file)
- [ ] Script execution (sh script.sh)

### Built-in Commands
- [x] Filesystem: ls, cat, cp, mv, rm, mkdir, touch, pwd, cd, find, chmod, du
- [x] Text: grep, head, tail, wc, sort, uniq, sed, cut, diff
- [x] System: echo, env, which, clear, exit, help, date, sleep, test, basename, dirname
- [x] Network: curl, wget (via URLSession bridge)
- [x] Claude: ask, run, edit, review, config, status
- [ ] git (basic operations via libgit2 or shell-out)
- [ ] tar/zip/unzip
- [ ] ssh/scp (via libssh2)
- [ ] nano/vi (basic text editor)
- [x] npm/node (JavaScriptCore engine + npm registry install)

### iOS App (Swift)
- [x] Terminal emulator with scrollback
- [x] ANSI escape code stripping
- [x] Command history (up/down arrows)
- [x] Quick-command bar (ls, pwd, clear, etc.)
- [x] Dark theme terminal UI
- [x] Settings view (API key, model, font size)
- [ ] Tab completion
- [ ] Keyboard shortcuts (Ctrl+C, Ctrl+D, Ctrl+L)
- [ ] Copy/paste from terminal output
- [ ] Split screen / multiple terminals
- [ ] File browser view

### Claude Integration
- [x] claude ask — free-form questions
- [x] claude run — multi-step tasks
- [x] claude edit — AI file editing
- [x] claude review — code review
- [x] claude config — API key management
- [x] claude status — connection check
- [x] Conversation history (last 20 messages)
- [ ] Streaming responses (show tokens as they arrive)
- [x] Tool use (let Claude run shell commands autonomously) — bash, read_file, write_file
- [x] claude code — full Claude Code mode (read files, edit, run commands) — agentic loop with 25-iteration cap
- [x] Multi-turn context with file awareness — auto-reads referenced files

### Build & Deploy
- [x] GitHub Actions CI (macOS runner)
- [x] Xcode project generation (xcodegen)
- [x] Simulator build + test
- [x] Device build (Release ARM64)
- [x] IPA validation (Info.plist, binary, architecture)
- [x] IPA packaging and artifact upload
- [x] Local C engine testing (Windows cross-compile)
- [x] SSH debug session on CI failure
- [ ] AltStore/Sideloadly install verified working
- [ ] TestFlight distribution
- [ ] App Store submission

---

## Key Technical Decisions

### Why C for the shell engine?
- Compiles to ARM64 natively — minimal overhead on iPhone
- No runtime dependencies — everything is statically linked into the app
- Can be tested locally on any platform (Windows/Linux/Mac)
- Swift calls C through the bridging header

### Why OpaquePointer workaround?
Swift can't directly access C structs with fixed-size pointer arrays (`char *env_keys[512]`).
Solution: `shell_helpers.c` provides accessor functions (`shell_get_cwd()`, `shell_is_running()`, etc.)
that Swift calls instead of accessing struct fields directly.

### Why URLSession for networking?
iOS doesn't allow raw sockets from sandboxed apps. curl/wget commands in C bridge
to Swift's URLSession via function pointer callbacks set during initialization.

### Sandbox constraints
- All file operations are confined to the app's Documents directory
- The shell's `/` maps to `Documents/` — users can't escape
- Network requires `NSAllowsArbitraryLoads` in Info.plist (set)
- No fork/exec — everything runs in-process

---

## Common Issues

### CI build fails at "Build for Simulator"
Check Swift compilation errors. Usually type mismatches in the C-Swift bridge.
The bridging header must match function signatures exactly.

### AltStore error 2005 / "data not in correct format"
The IPA needs ad-hoc signing (`CODE_SIGN_IDENTITY="-"`). Pure unsigned builds
(`CODE_SIGNING_ALLOWED=NO`) strip metadata that sideloading tools need.
Try Sideloadly as an alternative.

### Local test fails on Windows
Make sure MSYS2 gcc is in PATH: `export PATH="/c/msys64/mingw64/bin:$PATH"`
Windows needs `#ifdef _WIN32` guards for `mkdir`, `unistd.h`, `getpid`, etc.

---

## File Ownership

| File | Purpose | When to modify |
|------|---------|----------------|
| `shell.c` | Core interpreter, tokenizer, variable expansion | Adding shell syntax features |
| `cmd_system.c` | System commands + **dispatch table** | Adding ANY new command |
| `cmd_filesystem.c` | File operations | Adding file commands |
| `cmd_text.c` | Text processing | Adding text commands |
| `cmd_network.c` | Network (curl/wget) | Adding network commands |
| `shell_helpers.c` | Swift-safe struct accessors | When Shell struct changes |
| `ShellBridge.swift` | C-to-Swift bridge, callbacks | When C API changes |
| `ClaudeEngine.swift` | Anthropic API client | Claude integration changes |
| `TerminalView.swift` | Main UI | UI changes |
| `test_main.c` | Local test harness | When adding any command |
| `build-ios.yml` | CI pipeline | Build/deploy changes |
