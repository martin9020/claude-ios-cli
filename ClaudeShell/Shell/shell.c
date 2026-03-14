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

    int in_single_quote = 0;
    while (*p && ri < SHELL_MAX_LINE - 1) {
        if (*p == '\'' && !in_single_quote) { in_single_quote = 1; result[ri++] = *p++; continue; }
        if (*p == '\'' && in_single_quote) { in_single_quote = 0; result[ri++] = *p++; continue; }
        if (*p == '$' && !in_single_quote) {
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

// Pipe output capture state
static char _pipe_buf[SHELL_MAX_LINE * 4];
static int _pipe_len = 0;

static void pipe_capture_fn(const char *text, void *ctx) {
    (void)ctx;
    int tlen = strlen(text);
    if (_pipe_len + tlen < (int)sizeof(_pipe_buf) - 1) {
        memcpy(_pipe_buf + _pipe_len, text, tlen);
        _pipe_len += tlen;
        _pipe_buf[_pipe_len] = '\0';
    }
}

// Handle pipes: cmd1 | cmd2
// Captures left command output and feeds it as a temporary file to the right command
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

    // Trim whitespace from right command
    char *rp = right;
    while (*rp && isspace((unsigned char)*rp)) rp++;

    // Capture output of left command
    shell_output_fn saved_output = sh->output;
    void *saved_ctx = sh->output_ctx;
    _pipe_len = 0;
    _pipe_buf[0] = '\0';
    sh->output = pipe_capture_fn;
    sh->output_ctx = NULL;

    shell_exec(sh, left);

    // Restore output
    sh->output = saved_output;
    sh->output_ctx = saved_ctx;

    // Write captured output to a temp file for the right command to read.
    // Use cwd-relative name so text commands (which resolve_path via sh->root/cwd) can find it.
    char tmpfile[SHELL_MAX_PATH * 2];
    snprintf(tmpfile, sizeof(tmpfile), "%s%s.pipe_tmp", sh->cwd,
             sh->cwd[strlen(sh->cwd)-1] == '/' ? "" : "/");
    // Also compute the relative name for appending to the command
    static const char *pipe_tmpname = ".pipe_tmp";
    FILE *fp = fopen(tmpfile, "w");
    if (fp) {
        if (_pipe_len > 0) fwrite(_pipe_buf, 1, _pipe_len, fp);
        fclose(fp);
    }

    // Build right command with temp file as input arg
    // For text-processing commands (grep, head, tail, wc, sort, uniq, sed, cut, tr, cat),
    // append the temp file as the last argument
    char *right_cmd = rp;
    char piped_cmd[SHELL_MAX_LINE];
    // Tokenize just the command name to check
    char cmd_name[64] = {0};
    int ci = 0;
    const char *cp = right_cmd;
    while (*cp && !isspace((unsigned char)*cp) && ci < 63) {
        cmd_name[ci++] = *cp++;
    }
    cmd_name[ci] = '\0';

    const char *pipe_cmds[] = {"grep","head","tail","wc","sort","uniq","sed","cut","tr","cat",NULL};
    int is_pipe_cmd = 0;
    for (const char **pc = pipe_cmds; *pc; pc++) {
        if (strcmp(cmd_name, *pc) == 0) { is_pipe_cmd = 1; break; }
    }

    int ret;
    if (is_pipe_cmd) {
        snprintf(piped_cmd, sizeof(piped_cmd), "%.4080s %s", right_cmd, pipe_tmpname);
        ret = shell_exec(sh, piped_cmd);
    } else {
        // For other commands, just output the captured text and run the right command
        shell_printf(sh, "%s", _pipe_buf);
        ret = shell_exec(sh, right_cmd);
    }

    // Cleanup temp file
    remove(tmpfile);
    return ret;
}

// Redirect output capture state
static char _redirect_buf[SHELL_MAX_LINE * 4];
static int _redirect_len = 0;

static void redirect_capture_fn(const char *text, void *ctx) {
    (void)ctx;
    int tlen = strlen(text);
    if (_redirect_len + tlen < (int)sizeof(_redirect_buf) - 1) {
        memcpy(_redirect_buf + _redirect_len, text, tlen);
        _redirect_len += tlen;
        _redirect_buf[_redirect_len] = '\0';
    }
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
    char filepath[SHELL_MAX_PATH * 2];
    if (filename[0] == '/') {
        snprintf(filepath, sizeof(filepath), "%s%s", sh->root, filename);
    } else {
        snprintf(filepath, sizeof(filepath), "%s/%s", sh->cwd, filename);
    }

    // Capture output by temporarily replacing output function
    shell_output_fn saved_output = sh->output;
    void *saved_ctx = sh->output_ctx;
    _redirect_len = 0;
    _redirect_buf[0] = '\0';
    sh->output = redirect_capture_fn;
    sh->output_ctx = NULL;

    int ret = shell_exec(sh, line);

    // Restore output
    sh->output = saved_output;
    sh->output_ctx = saved_ctx;

    // Write captured output to file
    FILE *fp = fopen(filepath, append ? "a" : "w");
    if (fp) {
        if (_redirect_len > 0) {
            fwrite(_redirect_buf, 1, _redirect_len, fp);
        }
        fclose(fp);
    } else {
        shell_printf(sh, "claudeshell: cannot open '%s' for writing\n", filename);
        return 1;
    }

    return ret;
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

    // Check for output redirection (before pipes, so "cmd | cmd2 > file" works correctly)
    {
        int in_s = 0, in_d = 0;
        for (const char *p = linebuf; *p; p++) {
            if (*p == '\'' && !in_d) in_s = !in_s;
            else if (*p == '"' && !in_s) in_d = !in_d;
            else if (*p == '>' && !in_s && !in_d) {
                return handle_redirect(sh, linebuf);
            }
        }
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
