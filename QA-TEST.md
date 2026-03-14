# ClaudeShell QA Test Suite

## Previous Results: 43/50 passed (86%)

Sections 1-7 completed on 2026-03-14. Bugs fixed in this build:
- `uniq -c` — now supports -c (count) and -d (duplicates only) flags
- `cut -d':' -f2 file` — fixed delimiter parsing for -d':' combined format
- `cut -d':' -f1,3` — now supports multi-field selection
- `tr` via pipe — fully implemented (was a stub), supports ranges, -d, -s

---

## Section 9: Bug Fix Verification — paste this in Claude tab:

```
Test the 4 bug fixes. Run each command, verify output, write results to /qa_bugfix.md:

1. echo "banana" > /qa_test/sort2.txt && echo "apple" >> /qa_test/sort2.txt && echo "cherry" >> /qa_test/sort2.txt && echo "apple" >> /qa_test/sort2.txt
2. sort /qa_test/sort2.txt | uniq -c — expect: counts like "2 apple", "1 banana", "1 cherry"
3. echo "one:two:three" > /qa_test/cut2.txt
4. cut -d':' -f2 /qa_test/cut2.txt — expect: two
5. cut -d':' -f1,3 /qa_test/cut2.txt — expect: one:three
6. cut -d':' -f1 /qa_test/cut2.txt — expect: one
7. echo "Hello World" | tr 'a-z' 'A-Z' — expect: HELLO WORLD
8. echo "Hello World" | tr -d 'l' — expect: Heo Word
9. echo "hello    world" | tr -s ' ' — expect: hello world (squeeze spaces)

Write pass/fail for each to /qa_bugfix.md then cat /qa_bugfix.md
```

---

## Section 10: Dual Tabs Test — do manually:

1. Open app — see Shell tab (green) and Claude tab (purple) in status bar
2. Tap Shell tab — type `ls -la` — verify output shows
3. Tap Claude tab — should auto-enter Claude mode with banner
4. Type "hi" — verify Claude responds
5. Tap Shell tab — verify shell output is still there (not lost)
6. Tap Claude tab — verify Claude conversation is still there
7. In Claude tab, type `/exit` — should switch to Shell tab
8. In Shell tab, type `claude` — should switch to Claude tab

---

## Section 11: Files App Access — do manually:

1. Open iOS Files app
2. Navigate to "On My iPhone" > "ClaudeShell"
3. Verify you can see files: README.txt, qa_test folder, etc.
4. Tap a .md file — verify it opens and is readable
5. Try sharing a file via AirDrop or copy

---

## Section 12: Copy Button — do manually:

1. Run some commands in Shell tab
2. Tap yellow "copy" button
3. Open Notes app, paste — verify full terminal log appears
4. Switch to Claude tab, ask something
5. Tap "copy" — verify Claude tab's log is copied (not Shell tab's)
