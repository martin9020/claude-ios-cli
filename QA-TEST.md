# ClaudeShell QA Test — Regression Only

Previous: 43/50 passed. 4 bugs fixed. Run this to verify fixes.

---

## Paste this in Claude tab:

```
Run these 9 tests. For each: run the command, check output, mark PASS/FAIL. Write results to /qa_regression.md then cat it.

1. sort /qa_test/sort2.txt | uniq -c
   Expected: counts like "2 apple", "1 banana", "1 cherry"

2. echo "one:two:three" > /qa_test/cut3.txt && cut -d':' -f2 /qa_test/cut3.txt
   Expected: two

3. cut -d':' -f1,3 /qa_test/cut3.txt
   Expected: one:three

4. cut -d':' -f1 /qa_test/cut3.txt
   Expected: one

5. cut -c1-3 /qa_test/cut3.txt
   Expected: one

6. echo "Hello World" | tr 'a-z' 'A-Z'
   Expected: HELLO WORLD

7. echo "Hello World" | tr -d 'l'
   Expected: Heo Word

8. echo "hello    world" | tr -s ' '
   Expected: hello world

9. echo "aabbcc" | tr -s 'a'
   Expected: abbcc

Format results as markdown table with columns: #, Command, Expected, Got, Status
```
