#ifndef SHELL_H
#define SHELL_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SHELL_MAX_LINE 4096
#define SHELL_MAX_ARGS 256
#define SHELL_MAX_ENV  512
#define SHELL_MAX_PATH 1024

// Output callback — sends text back to Swift terminal
typedef void (*shell_output_fn)(const char *text, void *ctx);

// Shell state
typedef struct {
    char cwd[SHELL_MAX_PATH];
    char root[SHELL_MAX_PATH];       // sandbox root (Documents/)
    char *env_keys[SHELL_MAX_ENV];
    char *env_vals[SHELL_MAX_ENV];
    int env_count;
    shell_output_fn output;
    void *output_ctx;
    int last_exit_code;
    int running;
} Shell;

// Lifecycle
Shell *shell_create(const char *sandbox_root, shell_output_fn output, void *ctx);
void   shell_destroy(Shell *sh);

// Execute a line of input
int shell_exec(Shell *sh, const char *line);

// Environment
const char *shell_getenv(Shell *sh, const char *key);
void        shell_setenv(Shell *sh, const char *key, const char *val);

// Output helpers
void shell_printf(Shell *sh, const char *fmt, ...);

// Tokenizer
int shell_tokenize(const char *line, char **argv, int max_args);
void shell_free_tokens(char **argv, int argc);

#endif // SHELL_H
