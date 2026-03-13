# ClaudeShell — Claude Code CLI for iOS

A self-contained terminal environment for running Claude Code on iPhone/iOS.
Runs entirely in the app sandbox with zero external dependencies.

## Architecture

- Embedded POSIX shell interpreter (written in C, compiled for ARM64)
- Built-in Unix commands (ls, cat, cp, mv, rm, mkdir, curl, grep, etc.)
- Terminal emulator UI (SwiftUI)
- Claude Code engine (API-based, runs locally)
- Sandboxed filesystem (app Documents directory)

## Building

Requires Xcode 15+ and an Apple Developer account.

```bash
open ClaudeShell.xcodeproj
# Build & run on device or simulator
```

## Project Structure

```
ClaudeShell/
├── App/                    # SwiftUI app entry & views
│   ├── ClaudeShellApp.swift
│   ├── TerminalView.swift
│   └── SettingsView.swift
├── Shell/                  # Embedded shell engine (C)
│   ├── shell.h
│   ├── shell.c             # POSIX shell interpreter
│   ├── builtins.h
│   ├── builtins.c          # Built-in commands
│   ├── environment.h
│   └── environment.c       # Environment variables
├── Commands/               # Individual command implementations
│   ├── cmd_filesystem.c    # ls, cat, cp, mv, rm, mkdir, touch
│   ├── cmd_text.c          # grep, sed, head, tail, wc, sort
│   ├── cmd_network.c       # curl, ping, wget
│   └── cmd_system.c        # echo, env, export, which, pwd, cd
├── Claude/                 # Claude Code integration
│   ├── ClaudeEngine.swift
│   ├── APIClient.swift
│   └── TaskRunner.swift
├── Terminal/               # Terminal emulator
│   ├── TerminalEmulator.swift
│   ├── ANSIParser.swift
│   └── InputHandler.swift
└── Bridge/                 # Swift-C bridge
    └── ShellBridge.swift
```
