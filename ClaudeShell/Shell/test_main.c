/*
 * test_main.c — Local test harness for the shell engine.
 * Compile and run on Windows/Linux/Mac to test without iOS.
 *
 * Build:
 *   gcc -o shell_test test_main.c shell.c environment.c \
 *       ../Commands/cmd_filesystem.c ../Commands/cmd_text.c \
 *       ../Commands/cmd_system.c ../Commands/cmd_network.c \
 *       -DTEST_MODE
 */

#ifdef TEST_MODE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "shell.h"

static char test_output[8192];
static int test_output_len = 0;

static void test_output_fn(const char *text, void *ctx) {
    (void)ctx;
    int len = strlen(text);
    if (test_output_len + len < (int)sizeof(test_output) - 1) {
        memcpy(test_output + test_output_len, text, len);
        test_output_len += len;
        test_output[test_output_len] = '\0';
    }
}

static void reset_output(void) {
    test_output[0] = '\0';
    test_output_len = 0;
}

static int output_contains(const char *needle) {
    return strstr(test_output, needle) != NULL;
}

#define TEST(name) static void test_##name(Shell *sh)
#define RUN(name) do { \
    printf("  %-40s", #name); \
    reset_output(); \
    test_##name(sh); \
    printf(" PASS\n"); \
    passed++; \
} while(0)

#define ASSERT(cond) do { \
    if (!(cond)) { \
        printf(" FAIL\n    Assertion failed: %s\n    Output was: [%s]\n", #cond, test_output); \
        failed++; \
        return; \
    } \
} while(0)

static int passed = 0;
static int failed = 0;

// --- Tests ---

TEST(echo_simple) {
    shell_exec(sh, "echo hello");
    ASSERT(output_contains("hello"));
}

TEST(echo_multiple_words) {
    shell_exec(sh, "echo hello world foo");
    ASSERT(output_contains("hello world foo"));
}

TEST(pwd) {
    shell_exec(sh, "pwd");
    ASSERT(test_output_len > 0);
}

TEST(env_set_get) {
    shell_exec(sh, "MYVAR=testval123");
    reset_output();
    shell_exec(sh, "echo $MYVAR");
    ASSERT(output_contains("testval123"));
}

TEST(env_export) {
    shell_exec(sh, "export FOO=bar");
    reset_output();
    shell_exec(sh, "env");
    ASSERT(output_contains("FOO=bar"));
}

TEST(mkdir_ls) {
    shell_exec(sh, "mkdir testdir_a");
    reset_output();
    shell_exec(sh, "ls");
    ASSERT(output_contains("testdir_a"));
}

TEST(touch_cat) {
    shell_exec(sh, "touch myfile.txt");
    reset_output();
    shell_exec(sh, "ls");
    ASSERT(output_contains("myfile.txt"));
}

TEST(cd_and_back) {
    shell_exec(sh, "mkdir subdir");
    shell_exec(sh, "cd subdir");
    reset_output();
    shell_exec(sh, "pwd");
    ASSERT(output_contains("subdir"));
    shell_exec(sh, "cd ..");
}

TEST(and_operator) {
    shell_exec(sh, "true && echo and_works");
    ASSERT(output_contains("and_works"));
}

TEST(or_operator) {
    shell_exec(sh, "false || echo or_works");
    ASSERT(output_contains("or_works"));
}

TEST(exit_code) {
    shell_exec(sh, "false");
    reset_output();
    shell_exec(sh, "echo $?");
    ASSERT(output_contains("1"));
}

TEST(quoted_string) {
    shell_exec(sh, "echo \"hello world\"");
    ASSERT(output_contains("hello world"));
}

TEST(which_builtin) {
    shell_exec(sh, "which echo");
    ASSERT(output_contains("builtin"));
}

TEST(help_command) {
    shell_exec(sh, "help");
    ASSERT(output_contains("ClaudeShell") || output_contains("claude"));
}

TEST(date_command) {
    shell_exec(sh, "date");
    ASSERT(test_output_len > 0);
}

TEST(true_false) {
    int r1 = shell_exec(sh, "true");
    ASSERT(r1 == 0);
    int r2 = shell_exec(sh, "false");
    ASSERT(r2 == 1);
}

TEST(comment_ignored) {
    shell_exec(sh, "# this is a comment");
    ASSERT(test_output_len == 0);
}

TEST(empty_line) {
    int ret = shell_exec(sh, "   ");
    ASSERT(ret == 0);
    ASSERT(test_output_len == 0);
}

TEST(variable_in_braces) {
    shell_exec(sh, "GREETING=hello");
    reset_output();
    shell_exec(sh, "echo ${GREETING}_world");
    ASSERT(output_contains("hello_world"));
}

int main(void) {
    printf("\n=== ClaudeShell Engine Tests ===\n\n");

    // Create temp directory for sandbox
    #ifdef _WIN32
    const char *tmpdir = getenv("TEMP");
    if (!tmpdir) tmpdir = "C:\\Temp";
    char sandbox[512];
    snprintf(sandbox, sizeof(sandbox), "%s\\claudeshell_test_%d", tmpdir, (int)getpid());
    #else
    char sandbox[512];
    snprintf(sandbox, sizeof(sandbox), "/tmp/claudeshell_test_%d", (int)getpid());
    #endif

    // Create sandbox dir
    #ifdef _WIN32
    _mkdir(sandbox);
    #else
    mkdir(sandbox, 0755);
    #endif

    Shell *sh = shell_create(sandbox, test_output_fn, NULL);
    if (!sh) {
        printf("FATAL: Failed to create shell\n");
        return 1;
    }

    // Run all tests
    RUN(echo_simple);
    RUN(echo_multiple_words);
    RUN(pwd);
    RUN(env_set_get);
    RUN(env_export);
    RUN(mkdir_ls);
    RUN(touch_cat);
    RUN(cd_and_back);
    RUN(and_operator);
    RUN(or_operator);
    RUN(exit_code);
    RUN(quoted_string);
    RUN(which_builtin);
    RUN(help_command);
    RUN(date_command);
    RUN(true_false);
    RUN(comment_ignored);
    RUN(empty_line);
    RUN(variable_in_braces);

    printf("\n=== Results: %d passed, %d failed ===\n\n", passed, failed);

    shell_destroy(sh);
    return failed > 0 ? 1 : 0;
}

#endif // TEST_MODE
