# Plan: Pro Subscription Auth + Autonomous Claude

## Context

ClaudeShell needs two things: (1) Pro/Max subscription login so users don't need prepaid API credits, and (2) autonomous tool use so Claude can actually do things. User wants Pro auth first.

---

## Phase 1: Pro Subscription OAuth Login

### How it works (user perspective)

1. App runs `npm install @anthropic-ai/claude-code` on first launch (or from Settings)
2. App extracts the OAuth client_id from the installed package
3. User taps "Sign in with Claude Pro/Max" in Settings
4. Safari opens → user logs into their Claude account
5. App receives OAuth token → stored securely → done
6. All Claude commands now use the Pro subscription (no API key needed)

### Implementation (5 files)

**1. MODIFY: `ClaudeShell/Node/NpmManager.swift`**
- Add a method `installClaudeCode()` that runs `npm install @anthropic-ai/claude-code`
- This uses our existing npm install infrastructure (already working)

**2. NEW: `ClaudeShell/Claude/OAuthManager.swift` (~200 lines)**
- `extractClientId()` — reads the installed `@anthropic-ai/claude-code` package, searches the bundled `cli.js` for the OAuth client_id pattern (UUID format near oauth/authorize URL)
- `startOAuthFlow()` — standard PKCE flow:
  - Generate random `code_verifier` (43-128 chars)
  - Compute `code_challenge` = base64url(SHA256(code_verifier))
  - Open `ASWebAuthenticationSession` to:
    `https://console.anthropic.com/oauth/authorize?client_id={id}&response_type=code&redirect_uri={callback}&code_challenge={challenge}&code_challenge_method=S256`
  - Receive callback with auth code
  - POST to `https://api.anthropic.com/v1/oauth/token` to exchange code for tokens
- `refreshToken()` — auto-refresh when access token expires (every 8h)
- `getToken()` — returns current valid token
- Token storage in Keychain via `Security` framework
- Uses `ASWebAuthenticationSession` (built into iOS, handles Safari redirect)
- Uses `CryptoKit` for SHA256 (built into iOS)

**3. MODIFY: `ClaudeShell/Claude/ClaudeEngine.swift`**
- Add auth source: either API key or OAuth token
- Both go in `x-api-key` header (same format)
- `sendMessage()` checks OAuthManager first, falls back to API key

**4. MODIFY: `ClaudeShell/App/SettingsView.swift`**
- Add "Sign in with Claude Pro/Max" button (primary, top of settings)
- Show status: "Signed in" with green dot, or "Not signed in"
- "Sign Out" button when signed in
- Keep existing API key field below as "Alternative: Use API Key"
- Add "Install Claude Code package" button (needed before OAuth works)
- Show install progress

**5. MODIFY: `Package.swift`**
- No changes needed — OAuthManager.swift auto-discovered by xcodegen

### Why fetch client_id from npm package?
- Stays in sync with official Claude Code releases
- User runs `npm install @anthropic-ai/claude-code` → gets latest client_id
- If Anthropic changes it, user just updates the package
- No hardcoded values that go stale

---

## Phase 2: Autonomous Tool Use

After auth works, make Claude actually DO things.

### Changes (4 files)

**1. NEW: `ClaudeShell/Claude/ToolDefinitions.swift`**
- Define 3 tools: `bash`, `read_file`, `write_file`

**2. MODIFY: `ClaudeShell/Claude/ClaudeEngine.swift`**
- Add `tools` to API request
- Parse `tool_use` responses
- Agentic loop: tool_use → execute → tool_result → repeat until text
- 25 iteration safety cap

**3. MODIFY: `ClaudeShell/Bridge/ShellBridge.swift`**
- `executeAndCapture()` — run command, return output
- `executeTool()` — route bash/read/write to shell or FileManager
- `handleClaudeInputAgentic()` — use agentic loop

**4. MODIFY: `ClaudeShell/App/TerminalView.swift`**
- Show tool execution progress live
- "> Running: ls -la" as Claude works

---

## Implementation Order

1. `NpmManager.swift` — add `installClaudeCode()` method
2. `OAuthManager.swift` — new file, OAuth PKCE + client_id extraction
3. `ClaudeEngine.swift` — support OAuth token auth
4. `SettingsView.swift` — Pro login UI
5. Test OAuth flow → then move to Phase 2
6. `ToolDefinitions.swift` → `ClaudeEngine.swift` tool loop → `ShellBridge.swift` executor → `TerminalView.swift` progress

## Verification

1. CI build passes
2. On device: Settings → Install Claude Code package → Sign in with Pro → opens browser → login → token saved
3. Claude mode works with Pro subscription
4. (Phase 2) Claude autonomously creates files, runs commands.

This is the inital plan, get familiar with the project firstly, read claude.md, readme.md and implpement the plan, use this as background sourc-code https://github.com/anthropics/claude-code
"C:\Users\Martin PC\.claude\plans\vivid-doodling-marble.md" here is saved the plan.
C:\Users\Martin PC\claude-ios-cli here is our project folder.
Implement the plan strictly. Git push and test 

https://github.com/martin9020/claude-ios-cli/actions here are our actions so far, 28 workflows so far, we need to be build and download the ipa file at the end