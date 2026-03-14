# Plan: Pro Subscription Auth + Autonomous Claude

## Status: COMPLETED

Both phases are fully implemented and pushed to CI.

---

## Phase 1: Pro Subscription OAuth Login — DONE

### What was implemented:
1. **NpmManager.swift** — `installClaudeCode()` + full npm install with scoped package support, `-g` flag handling, proper tar extraction (GNU LongLink + pax headers), gzip decompression with retry buffer, dependency cycle detection
2. **OAuthManager.swift** — OAuth PKCE flow with ASWebAuthenticationSession, client_id extraction from npm package, Keychain token storage, auto-refresh on expiry
3. **ClaudeEngine.swift** — Dual auth (OAuth token first, API key fallback), dynamic model selection from Settings
4. **SettingsView.swift** — Pro/Max sign-in UI, Claude Code package install button, model picker, API key management

### How it works:
1. User taps "Install Claude Code Package" in Settings
2. App downloads `@anthropic-ai/claude-code` from npm registry
3. User taps "Sign in with Claude Pro/Max"
4. Safari opens → user logs into Anthropic account
5. OAuth token stored in Keychain → used for all API calls

---

## Phase 2: Autonomous Tool Use — DONE

### What was implemented:
1. **ToolDefinitions.swift** — 3 tools: `bash`, `read_file`, `write_file`
2. **ClaudeEngine.swift** — `sendMessageWithTools()` with tool parsing, handles text/toolUse/mixed responses, multiple concurrent tool uses
3. **ShellBridge.swift** — `executeAndCapture()`, `executeTool()` with sandbox path validation, `handleClaudeInputAgentic()` with 25-iteration loop, file context auto-loading
4. **TerminalView.swift** — Live tool progress display with orange indicators

### How it works:
1. User enters Claude mode (`claude` command)
2. Types natural language request
3. Claude calls tools autonomously (bash, read_file, write_file)
4. Each tool execution shown with ⚙ indicator
5. Loop continues until Claude responds with text or hits 25 iterations

---

## Additional Fixes Applied (Code Review)

- **Pipe support** — `cmd1 | cmd2` now captures left output and feeds to right command
- **Output redirection** — `cmd > file` and `cmd >> file` now capture and write to files
- **Sandbox security** — Path traversal protection (../ can't escape sandbox)
- **Model selection** — Settings picker now actually controls which model the API uses
- **API version** — Updated from 2023-06-01 to 2024-10-22
- **Crash fix** — Unsafe force unwrap of `argv[1]` in claude callback now guarded
- **Multiple tool uses** — API responses with multiple tool_use blocks all get executed
- **Circular require** — JsEngine detects and handles circular module dependencies
- **Module cache** — JsEngine caches loaded modules to avoid redundant loads
- **Dependency cycles** — NpmManager tracks packages being installed to prevent loops
- **Scoped packages** — `npm list` now shows `@scope/pkg` packages correctly
- **Test coverage** — 22 tests (was 19), added pipe and redirect tests
