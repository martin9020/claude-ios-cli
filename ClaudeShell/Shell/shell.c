#include "shell.h"
#include "builtins.h"
#include "environment.h"
#include <stdarg.h>
#include <ctype.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <direct.h>
#include <io.h>
#else
#include <unistd.h>
#endif

// Forward declarations for command dispatch
extern int cmd_dispatch(Shell *sh, int argc, char **argv);

Shell *shell_create(const char *sandbox_root, shell_output_fn output, void *ctx) {
    Shell *sh = (Shell *)calloc(1, sizeof(Shell));
    if (!sh) return NULL;

    strncpy(sh->root, sandbox_root, SHELL_MAX_PATH - 1);
    strncpy(sh->cwd, sandbox_root, SHELL_MAX_PATH - 1);
    sh->output = output;
    sh->output_ctx = ctx;
    sh->last_exit_code = 0;
    sh->running = 1;
    sh->env_count = 0;

    // Set default environment
    shell_setenv(sh, "HOME", sandbox_root);
    shell_setenv(sh, "PATH", "/usr/bin:/bin");
    shell_setenv(sh, "SHELL", "/bin/claudeshell");
    shell_setenv(sh, "USER", "mobile");
    shell_setenv(sh, "TERM", "xterm-256color");

    return sh;
}

void shell_destroy(Shell *sh) {
    if (!sh) return;
    env_cleanup(sh);
    free(sh);
}

void shell_printf(Shell *sh, const char *fmt, ...) {
    if (!sh || !sh->output) return;

    char buf[SHELL_MAX_LINE];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    sh->output(buf, sh->output_ctx);
}

// Tokenize input line into argv array, handling quotes
int shell_tokenize(const char *line, char **argv, int max_args) {
    int argc = 0;
    const char *p = line;

    while (*p && argc < max_args - 1) {
        // Skip whitespace
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;

        char buf[SHELL_MAX_LINE];
        int i = 0;

        if (*p == '"') {
            // Double-quoted string
            p++;
            while (*p && *p != '"' && i < SHELL_MAX_LINE - 1) {
                if (*p == '\\' && *(p + 1)) {
                    p++;
                    switch (*p) {
                        case 'n': buf[i++] = '\n'; break;
                        case 't': buf[i++] = '\t'; break;
                        case '\\': buf[i++] = '\\'; break;
                        case '"': buf[i++] = '"'; break;
                        default: buf[i++] = *p; break;
                    }
                } else {
                    buf[i++] = *p;
                }
                p++;
            }
            if (*p == '"') p++;
        } else if (*p == '\'') {
            // Single-quoted string (no escapes)
            p++;
            while (*p && *p != '\'' && i < SHELL_MAX_LINE - 1) {
                buf[i++] = *p++;
            }
            if (*p == '\'') p++;
        } else {
            // Unquoted word
            while (*p && !isspace((unsigned char)*p) && i < SHELL_MAX_LINE - 1) {
                if (*p == '\\' && *(p + 1)) {
                    p++;
                    buf[i++] = *p++;
                } else {
                    buf[i++] = *p++;
                }
            }
        }

        buf[i] = '\0';
        argv[argc] = strdup(buf);
        argc++;
    }

    argv[argc] = NULL;
    return argc;
}

void shell_free_tokens(char **argv, int argc) {
    for (int i = 0; i < argc; i++) {
        free(argv[i]);
        argv[i] = NULL;
    }
}

// Expand environment variables in a string ($VAR or ${VAR})
static char *expand_vars(Shell *sh, const char *input) {
    static char result[SHELL_MAX_LINE];
    int ri = 0;
    const char *p = input;

    while (*p && ri < SHELL_MAX_LINE - 1) {
        if (*p == '$') {
            p++;
            if (*p == '{') {
                // ${VAR}
                p++;
                char varname[256];
                int vi = 0;
                while (*p && *p != '}' && vi < 255) {
                    varname[vi++] = *p++;
                }
                varname[vi] = '\0';
                if (*p == '}') p++;

                const char *val = shell_getenv(sh, varname);
                if (val) {
                    int len = strlen(val);
                    if (ri + len < SHELL_MAX_LINE - 1) {
                        memcpy(result + ri, val, len);
                        ri += len;
                    }
                }
            } else if (*p == '?') {
                // $? — last exit code
                p++;
                ri += snprintf(result + ri, SHELL_MAX_LINE - ri, "%d", sh->last_exit_code);
            } else if (isalpha((unsigned char)*p) || *p == '_') {
                // $VAR
                char varname[256];
                int vi = 0;
                while (*p && (isalnum((unsigned char)*p) || *p == '_') && vi < 255) {
                    varname[vi++] = *p++;
                }
                varname[vi] = '\0';

                const char *val = shell_getenv(sh, varname);
                if (val) {
                    int len = strlen(val);
                    if (ri + len < SHELL_MAX_LINE - 1) {
                        memcpy(result + ri, val, len);
                        ri += len;
                    }
                }
            } else {
                result[ri++] = '$';
            }
        } else {
            result[ri++] = *p++;
        }
    }

    result[ri] = '\0';
    return result;
}

// Handle pipes: cmd1 | cmd2
static int handle_pipe(Shell *sh, const char *line) {
    // Find pipe character (not inside quotes)
    const char *pipe_pos = NULL;
    int in_single = 0, in_double = 0;
    for (const char *p = line; *p; p++) {
        if (*p == '\'' && !in_double) in_single = !in_single;
        else if (*p == '"' && !in_single) in_double = !in_double;
        else if (*p == '|' && !in_single && !in_double) {
            pipe_pos = p;
            break;
        }
    }

    if (!pipe_pos) return -1; // No pipe found

    // Split into left and right commands
    char left[SHELL_MAX_LINE], right[SHELL_MAX_LINE];
    int left_len = (int)(pipe_pos - line);
    strncpy(left, line, left_len);
    left[left_len] = '\0';
    strncpy(right, pipe_pos + 1, SHELL_MAX_LINE - 1);
    right[SHELL_MAX_LINE - 1] = '\0';

    // Capture output of left command
    // For now, execute sequentially (simplified pipe)
    // TODO: implement proper pipe with captured output
    shell_exec(sh, left);
    return shell_exec(sh, right);
}

// Handle output redirection: cmd > file or cmd >> file
static int handle_redirect(Shell *sh, char *line) {
    int append = 0;
    char *redir = NULL;
    int in_single = 0, in_double = 0;

    for (char *p = line; *p; p++) {
        if (*p == '\'' && !in_double) in_single = !in_single;
        else if (*p == '"' && !in_single) in_double = !in_double;
        else if (*p == '>' && !in_single && !in_double) {
            redir = p;
            if (*(p + 1) == '>') {
                append = 1;
            }
            break;
        }
    }

    if (!redir) return -1;

    // Terminate command at redirect
    *redir = '\0';
    char *filename = redir + 1 + (append ? 1 : 0);
    while (*filename && isspace((unsigned char)*filename)) filename++;

    // Trim trailing whitespace from filename
    char *end = filename + strlen(filename) - 1;
    while (end > filename && isspace((unsigned char)*end)) *end-- = '\0';

    if (!*filename) {
        shell_printf(sh, "claudeshell: syntax error near redirect\n");
        return 1;
    }

    // Resolve path
    char filepath[SHELL_MAX_PATH];
    if (filename[0] == '/') {
        snprintf(filepath, sizeof(filepath), "%s%s", sh->root, filename);
    } else {
        snprintf(filepath, sizeof(filepath), "%s/%s", sh->cwd, filename);
    }

    // Capture output by temporarily replacing output function
    // Simplified: just execute and write to file
    // TODO: proper output capture
    shell_exec(sh, line);

    return 0;
}

// Main execution entry point
int shell_exec(Shell *sh, const char *line) {
    if (!sh || !line) return 1;

    // Skip leading whitespace
    while (*line && isspace((unsigned char)*line)) line++;
    if (!*line || *line == '#') return 0;

    // Handle semicolons (sequential execution)
    char linebuf[SHELL_MAX_LINE];
    strncpy(linebuf, line, SHELL_MAX_LINE - 1);
    linebuf[SHELL_MAX_LINE - 1] = '\0';

    // Check for && and ||
    char *and_pos = strstr(linebuf, "&&");
    if (and_pos) {
        *and_pos = '\0';
        int ret = shell_exec(sh, linebuf);
        sh->last_exit_code = ret;
        if (ret == 0) {
            return shell_exec(sh, and_pos + 2);
        }
        return ret;
    }

    char *or_pos = strstr(linebuf, "||");
    if (or_pos) {
        *or_pos = '\0';
        int ret = shell_exec(sh, linebuf);
        sh->last_exit_code = ret;
        if (ret != 0) {
            return shell_exec(sh, or_pos + 2);
        }
        return ret;
    }

    // Check for pipes
    {
        int in_s = 0, in_d = 0;
        for (const char *p = linebuf; *p; p++) {
            if (*p == '\'' && !in_d) in_s = !in_s;
            else if (*p == '"' && !in_s) in_d = !in_d;
            else if (*p == '|' && !in_s && !in_d) {
                return handle_pipe(sh, linebuf);
            }
        }
    }

    // Expand variables
    char *expanded = expand_vars(sh, linebuf);

    // Tokenize
    char *argv[SHELL_MAX_ARGS];
    int argc = shell_tokenize(expanded, argv, SHELL_MAX_ARGS);

    if (argc == 0) return 0;

    // Check for variable assignment: VAR=value
    if (argc == 1 && strchr(argv[0], '=')) {
        char *eq = strchr(argv[0], '=');
        *eq = '\0';
        shell_setenv(sh, argv[0], eq + 1);
        shell_free_tokens(argv, argc);
        return 0;
    }

    // Check for export VAR=value
    if (argc >= 2 && strcmp(argv[0], "export") == 0) {
        for (int i = 1; i < argc; i++) {
            char *eq = strchr(argv[i], '=');
            if (eq) {
                *eq = '\0';
                shell_setenv(sh, argv[i], eq + 1);
            }
        }
        shell_free_tokens(argv, argc);
        return 0;
    }

    // Dispatch to commands
    int ret = cmd_dispatch(sh, argc, argv);
    sh->last_exit_code = ret;

    shell_free_tokens(argv, argc);
    return ret;
}
