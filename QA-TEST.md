# ClaudeShell QA Test Suite

**Status: 86/86 PASSED (100%)** — 2026-03-14

---

## Automated Tests (paste in Claude tab)

### Full Suite — 50 tests across 7 sections

```
Run a full QA sweep of ClaudeShell. Test every command category below. For each test, run the command, verify output, mark PASS/FAIL. Write a summary table to /qa_results.md then cat it.

FILESYSTEM: mkdir, touch, echo >, cat, ls, ls -la, cp, mv, rm, pwd, cd, cd .., cd /, find -name, find -type, du, chmod

TEXT: head -2, tail -2, wc -l, grep, grep -n, grep -i, grep -c, grep -v, sort, sort -r, sort|uniq, uniq -c, cut -d':' -f2, cut -d':' -f1,3, cut -c1-3, sed 's/old/new/', echo|tr 'a-z' 'A-Z', echo|tr -d 'l', echo|tr -s ' ', diff

SYSTEM: echo, echo -n, env, which, date, test -f, test -d, basename, dirname, true&&echo, false||echo

SHELL: VAR=val echo $VAR, ${VAR} expansion, $? exit code, echo>file redirect, echo>>file append, echo|grep pipe, "double quotes", 'single quotes', && chaining, || fallback, export

NETWORK: curl https://httpbin.org/get, curl -X POST

NODE: node -e "console.log('hi')", node -e "console.log(2+2)", npm list, npm help

CLAUDE TOOLS: write_file, read_file, ls via bash

Create test files as needed. Format: markdown table with #, Command, Expected, Got, Status.
```

---

## Manual Tests

### Dual Tabs ✅
1. Shell tab (green) + Claude tab (purple) visible in status bar
2. Shell tab: `ls -la` shows output
3. Claude tab: auto-enters Claude mode with banner
4. Switching preserves each tab's output independently
5. `/exit` in Claude switches to Shell tab
6. `claude` in Shell switches to Claude tab

### Files App Access ✅
1. iOS Files > On My iPhone > ClaudeShell
2. All sandbox files visible and readable
3. Files shareable via AirDrop/copy

### Copy Button ✅
1. Yellow "copy" button copies active tab's full log
2. Each tab copies its own log independently
