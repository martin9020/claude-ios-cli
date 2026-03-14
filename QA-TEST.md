# ClaudeShell QA Test Suite

Run this in Claude mode: `claude` then paste the test instructions below.

---

## Instructions for Claude

You are a QA agent. Test every command and feature listed below. For each test:
1. Run the command
2. Check the output
3. Mark PASS or FAIL
4. Write results to `/qa_results.md`

Start by running: `echo "Starting QA Test" > /qa_results.md`

---

## Test 1: Filesystem Commands

```
mkdir /qa_test
touch /qa_test/hello.txt
echo "Hello World" > /qa_test/hello.txt
cat /qa_test/hello.txt
# Expected: Hello World

ls /qa_test
ls -la /qa_test
# Expected: lists hello.txt

cp /qa_test/hello.txt /qa_test/hello_copy.txt
cat /qa_test/hello_copy.txt
# Expected: Hello World

mv /qa_test/hello_copy.txt /qa_test/renamed.txt
ls /qa_test
# Expected: hello.txt and renamed.txt

rm /qa_test/renamed.txt
ls /qa_test
# Expected: only hello.txt

pwd
cd /qa_test
pwd
# Expected: /qa_test
cd /
pwd
# Expected: /

find /qa_test -name "*.txt"
# Expected: finds hello.txt

du /qa_test
# Expected: shows size

chmod 755 /qa_test/hello.txt
# Expected: no error
```

## Test 2: Text Processing

```
echo "Line 1" > /qa_test/lines.txt
echo "Line 2" >> /qa_test/lines.txt
echo "Line 3" >> /qa_test/lines.txt
echo "Line 4" >> /qa_test/lines.txt
echo "Line 5" >> /qa_test/lines.txt

head -2 /qa_test/lines.txt
# Expected: Line 1, Line 2

tail -2 /qa_test/lines.txt
# Expected: Line 4, Line 5

wc -l /qa_test/lines.txt
# Expected: 5

grep "Line 3" /qa_test/lines.txt
# Expected: Line 3

grep -n "Line" /qa_test/lines.txt
# Expected: numbered lines

grep -i "line" /qa_test/lines.txt
# Expected: all lines (case insensitive)

grep -c "Line" /qa_test/lines.txt
# Expected: 5

grep -v "Line 3" /qa_test/lines.txt
# Expected: all except Line 3

echo "banana" > /qa_test/sort.txt
echo "apple" >> /qa_test/sort.txt
echo "cherry" >> /qa_test/sort.txt
echo "apple" >> /qa_test/sort.txt

sort /qa_test/sort.txt
# Expected: apple, apple, banana, cherry

sort /qa_test/sort.txt | uniq
# Expected: apple, banana, cherry

echo "one:two:three" > /qa_test/cut.txt
cut -d':' -f2 /qa_test/cut.txt
# Expected: two

sed 's/Line/Row/' /qa_test/lines.txt
# Expected: Row 1, Row 2, etc.

echo "Hello World" | tr 'a-z' 'A-Z'
# Expected: HELLO WORLD

echo "Line A" > /qa_test/d1.txt
echo "Line B" > /qa_test/d2.txt
diff /qa_test/d1.txt /qa_test/d2.txt
# Expected: shows difference
```

## Test 3: System Commands

```
echo "test output"
# Expected: test output

echo -n "no newline"
# Expected: no newline (no trailing newline)

env
# Expected: lists environment variables

which echo
# Expected: shell builtin

date
# Expected: current date

test -f /qa_test/hello.txt && echo "exists" || echo "missing"
# Expected: exists

test -d /qa_test && echo "is dir" || echo "not dir"
# Expected: is dir

basename /qa_test/hello.txt
# Expected: hello.txt

dirname /qa_test/hello.txt
# Expected: /qa_test

true && echo "true works"
# Expected: true works

false || echo "false works"
# Expected: false works

MYVAR=testing123
echo $MYVAR
# Expected: testing123

export TESTVAR=exported
env | grep TESTVAR
# Note: pipe might not pass env output correctly
```

## Test 4: Shell Features

```
# Variable expansion
NAME=Claude
echo "Hello ${NAME}"
# Expected: Hello Claude

# Exit code
false
echo $?
# Expected: 1

true
echo $?
# Expected: 0

# Output redirection
echo "redirect test" > /qa_test/redir.txt
cat /qa_test/redir.txt
# Expected: redirect test

echo "append test" >> /qa_test/redir.txt
cat /qa_test/redir.txt
# Expected: both lines

# Pipe
echo "hello" | grep hello
# Expected: hello

# Quoted strings
echo "hello world"
echo 'single quotes'
# Expected: hello world, single quotes

# Comments
# this should be ignored
echo "after comment"
# Expected: after comment

# && operator
echo "first" && echo "second"
# Expected: first, second

# || operator
false || echo "fallback"
# Expected: fallback
```

## Test 5: Network Commands

```
curl https://httpbin.org/get
# Expected: JSON response with headers

curl -X POST -d '{"test":true}' https://httpbin.org/post
# Expected: JSON response with data
```

## Test 6: Node.js / npm

```
node -e "console.log('Hello from JS')"
# Expected: Hello from JS

node -e "console.log(2+2)"
# Expected: 4

npm help
# Expected: shows npm usage

npm list
# Expected: shows installed packages (or empty)
```

## Test 7: Claude AI Features

```
/status
# Expected: shows auth status, model, tools

/help
# Expected: shows available commands

/clear
# Expected: clears conversation
```

## Test 8: Tool Use (Autonomous)

Ask Claude to:
- "Create a file called /qa_test/auto_created.txt with the text 'Claude wrote this'"
- Then verify: `cat /qa_test/auto_created.txt`
- "Read /qa_test/hello.txt and tell me what it says"
- "List all files in /qa_test"

## Final Step

Write all results to `/qa_results.md` with this format:
```
# QA Results - [date]

## Summary
- Total tests: X
- Passed: X
- Failed: X

## Details
| Test | Command | Expected | Actual | Status |
|------|---------|----------|--------|--------|
| 1.1 | mkdir /qa_test | no error | ... | PASS/FAIL |
...

## Known Issues
- ...
```

Then run: `cat /qa_results.md`
