# ClaudeShell — Claude Code for iOS

A terminal app for iPhone that brings Claude Code to your pocket. Run shell commands, talk to Claude, and let it autonomously create files, run scripts, and build projects — all from your phone.

## Features

- **40+ shell commands** — ls, cat, grep, sed, curl, node, npm, and more
- **Claude AI** — autonomous tool use with bash, read_file, write_file
- **Pro/Max login** — OAuth via your Claude subscription, no API key needed
- **Dual tabs** — Shell and Claude run side by side with independent output
- **Files app** — browse sandbox files from iOS Files
- **Copy button** — copy terminal log to clipboard
- **~40s CI builds** — push to master, get an IPA

## Quick Start

1. Download the IPA from [GitHub Actions](../../actions)
2. Install via [Sideloadly](https://sideloadly.io) (USB) or AltStore
3. Open the app → tap Settings (gear) → Sign in with Claude Pro/Max
4. Type `claude` or tap the Claude tab to start AI chat

## Shell Commands

| Category | Commands |
|----------|----------|
| Filesystem | `ls` `cat` `cp` `mv` `rm` `mkdir` `touch` `pwd` `cd` `find` `chmod` `du` |
| Text | `grep` `head` `tail` `wc` `sort` `uniq` `sed` `tr` `cut` `diff` |
| System | `echo` `env` `export` `which` `date` `sleep` `test` `basename` `dirname` |
| Utility | `serve` `base64` `whoami` `uptime` `open` |
| Network | `curl` `wget` |
| Node.js | `node <file.js>` `node -e "code"` `npm install` `npm list` |
| Shell | pipes `\|`  redirects `>` `>>`  variables `$VAR`  operators `&&` `\|\|` |

## Local HTTP Server

```
serve              # start server on port 8080
serve 3000         # start on custom port
serve stop         # stop server
serve status       # check if running
```

Then open `http://localhost:8080` in Safari to view your HTML files.

## Claude AI Mode

Type `claude` or tap the Claude tab. Claude can run commands, create files, and chain operations autonomously (up to 75 per turn).

```
claude> create a python script that fetches weather data
⚙ bash: mkdir -p projects
⚙ write_file: projects/weather.py
⚙ bash: cat projects/weather.py
Done! Created projects/weather.py
```

## Architecture

```
TerminalView (SwiftUI)
├── Shell Tab ──→ ShellBridge ──→ shell.c / cmd_*.c (C engine)
└── Claude Tab ─→ ClaudeEngine ─→ Anthropic API (Bearer + oauth beta)
                  └── Tools: bash, read_file, write_file
```

- **C shell engine** — 40+ commands, compiles to ARM64, zero dependencies
- **Swift bridge** — connects C callbacks to iOS via function pointers
- **OAuth** — PKCE flow via claude.ai, Bearer token with `anthropic-beta: oauth-2025-04-20`
- **Sandbox** — all files in app's Documents directory, accessible via iOS Files

## Build

Push triggers CI (~40s):

```bash
git push origin master
gh run download --name ClaudeShell-sideload --dir Desktop
```

Local tests (Windows/Mac/Linux):

```bash
cd ClaudeShell/Shell
gcc -o test test_main.c shell.c shell_helpers.c environment.c \
    ../Commands/cmd_*.c -DTEST_MODE -I.
./test  # 22 passed, 0 failed
```

## QA Status

**64/70 tests passing (91.4%)** — 0 hard failures. See [QA-TEST.md](QA-TEST.md).

## Distribution

| Method | Cost | Notes |
|--------|------|-------|
| Sideloadly | Free | USB install, re-sign every 7 days |
| AltStore | Free | On-device, re-sign every 7 days |
| TestFlight | $99/yr | Share via link, no re-signing |

## License

MIT
