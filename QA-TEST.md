# ClaudeShell QA Test Suite

**Last verified:** 2026-03-14
**Dual Tabs:** PASSED ✅ | **Files App:** PASSED ✅ | **Copy Button:** PASSED ✅

---

## Full Suite (paste in Claude tab)

```
Run a full QA sweep of ClaudeShell. Test every command category below. For each test, run the command, verify output, mark PASS/FAIL. Write a summary table to /qa_results.md then cat it.

FILESYSTEM: mkdir, touch, echo >, cat, ls, ls -la, cp, mv, rm, pwd, cd, cd .., cd /, find -name, find -type, du, chmod

TEXT: head -2, tail -2, wc -l, grep, grep -n, grep -i, grep -c, grep -v, sort, sort -r, sort|uniq, uniq -c, cut -d':' -f2, cut -d':' -f1,3, cut -c1-3, sed 's/old/new/', echo|tr 'a-z' 'A-Z', echo|tr -d 'l', echo|tr -s ' ', diff

SYSTEM: echo, echo -n, env, which, date, test -f, test -d, basename, dirname, true&&echo, false||echo

SHELL: VAR=val echo $VAR, ${VAR} expansion, echo>file redirect, echo>>file append, echo|grep pipe, "double quotes", 'single quotes', && chaining, || fallback, export

NETWORK: curl https://httpbin.org/get, curl -X POST

NODE: node -e "console.log('hi')", node -e "console.log(2+2)", npm list, npm help

CLAUDE TOOLS: write_file, read_file, ls via bash

Create test files as needed. Format: markdown table with #, Command, Expected, Got, Status.
```
