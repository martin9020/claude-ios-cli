# ClaudeShell — Claude Code CLI for iOS

A self-contained terminal environment that brings Claude Code to iPhone.
Embedded POSIX shell + Claude AI in one app. No server needed. Runs entirely in the iOS sandbox.

## Goal

Run Claude Code on iPhone the same way you'd use `cmd.exe` or a Linux terminal on a PC — with bash-like commands, file operations, curl, and a direct Claude AI integration.

## Current Status

| Component | Status | Notes |
|-----------|--------|-------|
| C Shell Engine | DONE | 40+ built-in commands, env vars, pipes, &&/\|\| |
| Shell Tests (local) | PASS (19/19) | Cross-platform: runs on Windows, Linux, macOS |
| Swift App (iOS) | DONE | Terminal UI, settings, ANSI color support |
| Claude AI Integration | DONE | `claude ask/run/edit/review` via Anthropic API |
| Network (curl/wget) | DONE | URLSession bridge for HTTP requests |
| CI Build (GitHub Actions) | GREEN | Builds, tests, packages IPA automatically |
| IPA Sideloading | IN PROGRESS | AltStore/Sideloadly installation |

## Architecture

```
iPhone App Sandbox
+--------------------------------------------------+
|  SwiftUI Terminal View                           |
|  +--------------------------------------------+ |
|  | ~ $ claude ask "explain this code"          | |
|  | Thinking...                                 | |
|  | The code implements a binary search...      | |
|  +--------------------------------------------+ |
|                      |                            |
|  ShellBridge (Swift-C Bridge)                    |
|                      |                            |
|  +--------------------------------------------+ |
|  | C Shell Engine (shell.c)                    | |
|  |  - Tokenizer, variable expansion           | |
|  |  - &&, ||, pipes, quotes                   | |
|  |  - Command dispatch table                  | |
|  +--------------------------------------------+ |
|       |          |           |          |        |
|  Filesystem   Text      Network    Claude AI    |
|  ls,cat,cp   grep,sed   curl,wget  ask,run     |
|  mkdir,rm    head,tail             edit,review   |
|  find,touch  wc,sort                            |
+--------------------------------------------------+
       |                        |
   App Documents/          Anthropic API
   (sandboxed fs)        (api.anthropic.com)
```

## Built-in Commands

### Filesystem
`ls` `cat` `cp` `mv` `rm` `mkdir` `touch` `pwd` `cd` `find` `chmod` `du`

### Text Processing
`grep` `head` `tail` `wc` `sort` `uniq` `sed` `tr` `cut` `diff`

### System
`echo` `env` `export` `which` `clear` `exit` `help` `date` `sleep` `test` `true` `false` `basename` `dirname`

### Network
`curl` `wget`

### Claude AI
`claude ask <prompt>` `claude run <task>` `claude edit <file>` `claude review <file>` `claude config` `claude status`

### Shell Features
- Environment variables: `VAR=value`, `$VAR`, `${VAR}`
- Operators: `&&`, `||`, `$?`
- Quoting: `"double"`, `'single'`
- Comments: `# ignored`

## Project Structure

```
claude-ios-cli/
├── .github/workflows/
│   ├── build-ios.yml          # Full iOS build, test, IPA packaging
│   └── test-shell.yml         # Cross-platform C engine tests
├── ClaudeShell/
│   ├── App/
│   │   ├── ClaudeShellApp.swift    # App entry point
│   │   ├── TerminalView.swift      # Main terminal UI
│   │   └── SettingsView.swift      # API key, model, font settings
│   ├── Shell/
│   │   ├── shell.c / shell.h       # Core shell interpreter
│   │   ├── environment.c / .h      # Environment variable store
│   │   ├── builtins.c / .h         # Command declarations
│   │   ├── shell_helpers.c / .h    # Swift-safe struct accessors
│   │   └── test_main.c             # Local test harness
│   ├── Commands/
│   │   ├── cmd_filesystem.c        # ls, cat, cp, mv, rm, mkdir, etc.
│   │   ├── cmd_text.c              # grep, head, tail, wc, sort, etc.
│   │   ├── cmd_network.c           # curl, wget (bridges to Swift)
│   │   └── cmd_system.c            # echo, env, help + dispatch table
│   ├── Claude/
│   │   └── ClaudeEngine.swift      # Anthropic Messages API client
│   ├── Terminal/
│   │   └── TerminalEmulator.swift  # Output buffer, ANSI parser
│   ├── Bridge/
│   │   ├── ShellBridge.swift       # C-to-Swift bridge + callbacks
│   │   └── ClaudeShell-Bridging-Header.h
│   ├── Tests/
│   │   └── ShellTests.swift        # iOS unit tests
│   └── Info.plist
├── CLAUDE.md                       # Dev guide for AI assistants
├── INSTALL.md                      # Installation walkthrough
├── ExportOptions.plist             # App Store export config
├── generate-xcodeproj.sh           # Xcode project generator
└── Package.swift                   # SPM manifest
```

## Quick Start

### Test locally (Windows/Linux/Mac)
```bash
cd ClaudeShell/Shell
gcc -o shell_test test_main.c shell.c shell_helpers.c environment.c \
    ../Commands/cmd_system.c ../Commands/cmd_filesystem.c \
    ../Commands/cmd_text.c ../Commands/cmd_network.c -DTEST_MODE -I.
./shell_test
```

### Build iOS app (via GitHub Actions)
```bash
git push origin master          # Auto-triggers build + test
gh run watch                    # Watch CI progress
gh run download <run-id> --name ClaudeShell-sideload  # Download IPA
```

### Install on iPhone
See [INSTALL.md](INSTALL.md) for AltStore, Sideloadly, TestFlight, or App Store paths.

## Development Workflow

See [CLAUDE.md](CLAUDE.md) for the full development checklist and CI/CD pipeline.
