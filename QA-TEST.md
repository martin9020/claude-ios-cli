# ClaudeShell QA Test Suite

## How to Run

Enter `claude` mode, then paste ONE section at a time. After each section completes, paste the next one.

---

## Section 1: Filesystem — EXECUTED (needs output verification)

Commands ran without crashing. Need to verify actual output.
Re-run to confirm: paste the Section 2 block below (it includes filesystem too).

---

## Section 2: Text Processing — paste this:

```
Test the remaining text commands. Run each, check output, write results to /qa_results_text.md:

1. echo "banana" > /qa_test/sort.txt && echo "apple" >> /qa_test/sort.txt && echo "cherry" >> /qa_test/sort.txt && echo "apple" >> /qa_test/sort.txt
2. sort /qa_test/sort.txt — expect: apple, apple, banana, cherry
3. sort -r /qa_test/sort.txt — expect: cherry, banana, apple, apple
4. sort /qa_test/sort.txt | uniq — expect: apple, banana, cherry (test pipe+uniq)
5. uniq -c /qa_test/sort.txt — expect: count duplicates
6. echo "one:two:three" > /qa_test/cut.txt
7. cut -d':' -f2 /qa_test/cut.txt — expect: two
8. cut -d':' -f1,3 /qa_test/cut.txt — expect: one:three
9. sed 's/apple/APPLE/' /qa_test/sort.txt — expect: APPLE replacements
10. echo "Hello World" | tr 'a-z' 'A-Z' — expect: HELLO WORLD
11. echo "Line A" > /qa_test/d1.txt && echo "Line B" > /qa_test/d2.txt
12. diff /qa_test/d1.txt /qa_test/d2.txt — expect: shows difference

Write pass/fail for each to /qa_results_text.md then cat /qa_results_text.md
```

---

## Section 3: System Commands — paste this:

```
Test system commands. Run each, check output, write results to /qa_results_sys.md:

1. echo "test output" — expect: test output
2. echo -n "no newline" — expect: no trailing newline
3. env — expect: lists HOME, PATH, etc.
4. which echo — expect: shell builtin
5. which ls — expect: shell builtin
6. date — expect: current date/time
7. test -f /qa_test/hello.txt && echo "exists" — expect: exists
8. test -d /qa_test && echo "is dir" — expect: is dir
9. test -f /nonexistent || echo "missing" — expect: missing
10. basename /qa_test/hello.txt — expect: hello.txt
11. dirname /qa_test/hello.txt — expect: /qa_test
12. true && echo "true works" — expect: true works
13. false || echo "false works" — expect: false works

Write pass/fail for each to /qa_results_sys.md then cat /qa_results_sys.md
```

---

## Section 4: Shell Features — paste this:

```
Test shell features. Run each, check output, write results to /qa_results_shell.md:

1. MYVAR=hello123 && echo $MYVAR — expect: hello123
2. NAME=Claude && echo "Hello ${NAME}" — expect: Hello Claude
3. false && echo $? — then: echo $? — expect: 1
4. true && echo $? — expect: 0
5. echo "redirect" > /qa_test/redir.txt && cat /qa_test/redir.txt — expect: redirect
6. echo "appended" >> /qa_test/redir.txt && cat /qa_test/redir.txt — expect: both lines
7. echo "pipe test" | grep pipe — expect: pipe test
8. echo "hello world" — expect: hello world
9. echo 'single quotes' — expect: single quotes
10. echo "first" && echo "second" — expect: first then second
11. false || echo "fallback" — expect: fallback
12. export TESTVAR=exported && echo $TESTVAR — expect: exported

Write pass/fail for each to /qa_results_shell.md then cat /qa_results_shell.md
```

---

## Section 5: Network — paste this:

```
Test network commands. Write results to /qa_results_net.md:

1. curl https://httpbin.org/get — expect: JSON response
2. curl -X POST -d '{"test":true}' https://httpbin.org/post — expect: JSON with data

Write pass/fail to /qa_results_net.md then cat /qa_results_net.md
```

---

## Section 6: Node.js — paste this:

```
Test node/npm. Write results to /qa_results_node.md:

1. node -e "console.log('Hello from JS')" — expect: Hello from JS
2. node -e "console.log(2+2)" — expect: 4
3. node -e "console.log(JSON.stringify({a:1,b:2}))" — expect: {"a":1,"b":2}
4. npm list — expect: shows packages or empty
5. npm help — expect: shows usage

Write pass/fail to /qa_results_node.md then cat /qa_results_node.md
```

---

## Section 7: Claude Features — paste this:

```
Test your own features. Write results to /qa_results_claude.md:

1. Create file /qa_test/auto.txt with text "Claude wrote this automatically"
2. Read /qa_test/auto.txt and confirm contents
3. List all files in /qa_test
4. Read /qa_test/hello.txt and tell me what it says
5. Write a simple Python script to /qa_test/hello.py that prints "Hello from Python"
6. Read it back to verify

Write pass/fail to /qa_results_claude.md then cat /qa_results_claude.md
```

---

## Section 8: Final Summary — paste this:

```
Read all QA result files and create a combined summary:
cat /qa_results_text.md
cat /qa_results_sys.md
cat /qa_results_shell.md
cat /qa_results_net.md
cat /qa_results_node.md
cat /qa_results_claude.md

Then write a final summary to /qa_final.md with:
- Total tests run
- Total passed
- Total failed
- List of any failures with details
- Overall verdict

Then cat /qa_final.md
```
