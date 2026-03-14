// System-level commands and the main dispatch table

#include "../Shell/builtins.h"
#include "../Shell/environment.h"
#include <time.h>
#include <ctype.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <windows.h>
#define access _access
#define F_OK 0
#define sleep(s) Sleep((s)*1000)
#else
#include <unistd.h>
#endif

// Claude command — bridges to Swift ClaudeEngine
typedef void (*claude_handler_fn)(Shell *sh, int argc, char **argv);
static claude_handler_fn _claude_handler = NULL;

void shell_set_claude_handler(claude_handler_fn handler) {
    _claude_handler = handler;
}

// Serve command — bridges to Swift HttpServer
typedef void (*serve_handler_fn)(Shell *sh, int argc, char **argv);
static serve_handler_fn _serve_handler = NULL;

void shell_set_serve_handler(serve_handler_fn handler) {
    _serve_handler = handler;
}

// Node/npm command — bridges to Swift JsEngine/NpmManager
typedef void (*node_handler_fn)(Shell *sh, int argc, char **argv);
static node_handler_fn _node_handler = NULL;
static node_handler_fn _npm_handler = NULL;

void shell_set_node_handler(node_handler_fn handler) {
    _node_handler = handler;
}

void shell_set_npm_handler(node_handler_fn handler) {
    _npm_handler = handler;
}

// --- System Commands ---

int cmd_echo(Shell *sh, int argc, char **argv) {
    int newline = 1;
    int interpret_escapes = 0;
    int start = 1;

    // Parse flags
    while (start < argc && argv[start][0] == '-') {
        if (strcmp(argv[start], "-n") == 0) { newline = 0; start++; }
        else if (strcmp(argv[start], "-e") == 0) { interpret_escapes = 1; start++; }
        else break;
    }

    for (int i = start; i < argc; i++) {
        if (i > start) shell_printf(sh, " ");
        if (interpret_escapes) {
            const char *p = argv[i];
            while (*p) {
                if (*p == '\\' && *(p + 1)) {
                    p++;
                    switch (*p) {
                        case 'n': shell_printf(sh, "\n"); break;
                        case 't': shell_printf(sh, "\t"); break;
                        case '\\': shell_printf(sh, "\\"); break;
                        case 'r': shell_printf(sh, "\r"); break;
                        case '0': shell_printf(sh, "\0"); break;
                        default: shell_printf(sh, "\\%c", *p); break;
                    }
                } else {
                    shell_printf(sh, "%c", *p);
                }
                p++;
            }
        } else {
            shell_printf(sh, "%s", argv[i]);
        }
    }
    if (newline) shell_printf(sh, "\n");
    return 0;
}

int cmd_env(Shell *sh, int argc, char **argv) {
    (void)argc; (void)argv;
    for (int i = 0; i < sh->env_count; i++) {
        shell_printf(sh, "%s=%s\n", sh->env_keys[i], sh->env_vals[i]);
    }
    return 0;
}

int cmd_which(Shell *sh, int argc, char **argv) {
    if (argc < 2) { shell_printf(sh, "usage: which command\n"); return 1; }
    const char *builtins[] = {
        "echo","env","which","clear","exit","help","date","sleep",
        "true","false","test","basename","dirname","tee","xargs",
        "ls","cat","cp","mv","rm","mkdir","touch","pwd","cd",
        "find","chmod","du","ln",
        "grep","head","tail","wc","sort","uniq","sed","tr","cut","diff",
        "curl","wget","node","npm","serve",
        "base64","whoami","uptime","open","claude", NULL
    };
    for (const char **b = builtins; *b; b++) {
        if (strcmp(argv[1], *b) == 0) {
            shell_printf(sh, "%s: shell builtin\n", argv[1]);
            return 0;
        }
    }
    shell_printf(sh, "%s: not found\n", argv[1]);
    return 1;
}

int cmd_clear(Shell *sh, int argc, char **argv) {
    (void)argc; (void)argv;
    shell_printf(sh, "\033[2J\033[H");
    return 0;
}

int cmd_exit(Shell *sh, int argc, char **argv) {
    int code = 0;
    if (argc > 1) code = atoi(argv[1]);
    sh->running = 0;
    return code;
}

int cmd_help(Shell *sh, int argc, char **argv) {
    (void)argc; (void)argv;
    shell_printf(sh, "\033[1;36mClaudeShell v1.0\033[0m — Terminal for iOS\n\n");
    shell_printf(sh, "\033[1mFilesystem:\033[0m  ls cat cp mv rm mkdir touch pwd cd find chmod du\n");
    shell_printf(sh, "\033[1mText:\033[0m        grep head tail wc sort uniq sed tr cut diff\n");
    shell_printf(sh, "\033[1mSystem:\033[0m      echo env export which clear exit help date sleep\n");
    shell_printf(sh, "             base64 whoami uptime open\n");
    shell_printf(sh, "\033[1mNetwork:\033[0m     curl wget\n");
    shell_printf(sh, "\033[1mServer:\033[0m      serve [port]            — Start HTTP file server\n");
    shell_printf(sh, "             serve stop              — Stop server\n");
    shell_printf(sh, "             serve status            — Show server status\n");
    shell_printf(sh, "\033[1mNode.js:\033[0m     node <file.js>          — Run JavaScript\n");
    shell_printf(sh, "             npm install <pkg>        — Install npm package\n");
    shell_printf(sh, "             npm list                 — List installed packages\n");
    shell_printf(sh, "\033[1mClaude AI:\033[0m   claude                  — Enter interactive AI chat\n");
    shell_printf(sh, "             claude <message>         — One-shot AI question\n");
    shell_printf(sh, "\033[1mShell:\033[0m       VAR=val  $VAR  ${VAR}  &&  ||  \"quotes\"  'quotes'\n");
    shell_printf(sh, "\nType 'help <command>' for details.\n");
    return 0;
}

int cmd_date(Shell *sh, int argc, char **argv) {
    (void)argc; (void)argv;
    time_t t = time(NULL);
    char *s = ctime(&t);
    if (s) shell_printf(sh, "%s", s);
    return 0;
}

int cmd_sleep(Shell *sh, int argc, char **argv) {
    (void)sh;
    if (argc < 2) { shell_printf(sh, "usage: sleep seconds\n"); return 1; }
    sleep((unsigned)atoi(argv[1]));
    return 0;
}

int cmd_true_cmd(Shell *sh, int argc, char **argv) {
    (void)sh; (void)argc; (void)argv; return 0;
}

int cmd_false_cmd(Shell *sh, int argc, char **argv) {
    (void)sh; (void)argc; (void)argv; return 1;
}

int cmd_test(Shell *sh, int argc, char **argv) {
    if (argc < 2) return 1;
    if (argc >= 3 && strcmp(argv[1], "-f") == 0) {
        char path[SHELL_MAX_PATH * 2];
        if (argv[2][0] == '/') snprintf(path, sizeof(path), "%s%s", sh->root, argv[2]);
        else snprintf(path, sizeof(path), "%s/%s", sh->cwd, argv[2]);
        return access(path, F_OK) == 0 ? 0 : 1;
    }
    if (argc >= 3 && strcmp(argv[1], "-d") == 0) {
        char path[SHELL_MAX_PATH * 2];
        if (argv[2][0] == '/') snprintf(path, sizeof(path), "%s%s", sh->root, argv[2]);
        else snprintf(path, sizeof(path), "%s/%s", sh->cwd, argv[2]);
        struct stat st;
        return (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) ? 0 : 1;
    }
    if (argc >= 3 && strcmp(argv[1], "-z") == 0) return strlen(argv[2]) == 0 ? 0 : 1;
    if (argc >= 3 && strcmp(argv[1], "-n") == 0) return strlen(argv[2]) > 0 ? 0 : 1;
    if (argc >= 4 && strcmp(argv[2], "=") == 0) return strcmp(argv[1], argv[3]) == 0 ? 0 : 1;
    if (argc >= 4 && strcmp(argv[2], "!=") == 0) return strcmp(argv[1], argv[3]) != 0 ? 0 : 1;
    return 1;
}

int cmd_basename(Shell *sh, int argc, char **argv) {
    if (argc < 2) { shell_printf(sh, "usage: basename path [suffix]\n"); return 1; }
    const char *base = strrchr(argv[1], '/');
    base = base ? base + 1 : argv[1];
    char result[SHELL_MAX_PATH];
    strncpy(result, base, sizeof(result) - 1);
    if (argc >= 3) {
        int rlen = strlen(result), slen = strlen(argv[2]);
        if (rlen > slen && strcmp(result + rlen - slen, argv[2]) == 0)
            result[rlen - slen] = '\0';
    }
    shell_printf(sh, "%s\n", result);
    return 0;
}

int cmd_dirname(Shell *sh, int argc, char **argv) {
    if (argc < 2) { shell_printf(sh, "usage: dirname path\n"); return 1; }
    char path[SHELL_MAX_PATH];
    strncpy(path, argv[1], sizeof(path) - 1);
    char *last = strrchr(path, '/');
    if (last) { if (last == path) shell_printf(sh, "/\n"); else { *last = '\0'; shell_printf(sh, "%s\n", path); } }
    else shell_printf(sh, ".\n");
    return 0;
}

int cmd_tee(Shell *sh, int argc, char **argv) {
    (void)argc; (void)argv;
    shell_printf(sh, "tee: requires pipe support\n");
    return 1;
}

int cmd_xargs(Shell *sh, int argc, char **argv) {
    (void)argc; (void)argv;
    shell_printf(sh, "xargs: requires pipe support\n");
    return 1;
}

int cmd_node(Shell *sh, int argc, char **argv) {
    if (_node_handler) {
        _node_handler(sh, argc, argv);
        return sh->last_exit_code;
    }
    shell_printf(sh, "node: JavaScript engine (handled by iOS app)\n");
    return 0;
}

int cmd_npm(Shell *sh, int argc, char **argv) {
    if (_npm_handler) {
        _npm_handler(sh, argc, argv);
        return sh->last_exit_code;
    }
    shell_printf(sh, "npm: package manager (handled by iOS app)\n");
    return 0;
}

int cmd_serve(Shell *sh, int argc, char **argv) {
    if (_serve_handler) {
        _serve_handler(sh, argc, argv);
        return sh->last_exit_code;
    }
    shell_printf(sh, "serve: HTTP server (handled by iOS app)\n");
    return 0;
}

int cmd_base64(Shell *sh, int argc, char **argv) {
    if (argc < 2) {
        shell_printf(sh, "Usage: base64 encode <file>\n");
        shell_printf(sh, "       base64 decode <file> [output]\n");
        return 1;
    }

    int decode = 0;
    const char *filename = NULL;
    const char *outfile = NULL;
    (void)outfile;

    if (strcmp(argv[1], "encode") == 0) {
        decode = 0;
        if (argc >= 3) filename = argv[2];
    } else if (strcmp(argv[1], "decode") == 0) {
        decode = 1;
        if (argc >= 3) filename = argv[2];
        if (argc >= 4) outfile = argv[3];
    } else {
        // Treat as encode of a file
        filename = argv[1];
    }

    if (!filename) {
        shell_printf(sh, "base64: missing filename\n");
        return 1;
    }

    char path[SHELL_MAX_PATH * 2];
    if (filename[0] == '/') snprintf(path, sizeof(path), "%s%s", sh->root, filename);
    else snprintf(path, sizeof(path), "%s/%s", sh->cwd, filename);

    FILE *f = fopen(path, "rb");
    if (!f) {
        shell_printf(sh, "base64: %s: No such file\n", filename);
        return 1;
    }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size > 1024 * 1024) { // 1MB limit
        shell_printf(sh, "base64: file too large (max 1MB)\n");
        fclose(f);
        return 1;
    }

    unsigned char *buf = (unsigned char *)malloc(size);
    if (!buf) { fclose(f); return 1; }
    fread(buf, 1, size, f);
    fclose(f);

    if (!decode) {
        // Encode
        static const char b64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        int i;
        for (i = 0; i + 2 < size; i += 3) {
            shell_printf(sh, "%c%c%c%c",
                b64[buf[i] >> 2],
                b64[((buf[i] & 3) << 4) | (buf[i+1] >> 4)],
                b64[((buf[i+1] & 0xF) << 2) | (buf[i+2] >> 6)],
                b64[buf[i+2] & 0x3F]);
        }
        if (i < size) {
            shell_printf(sh, "%c", b64[buf[i] >> 2]);
            if (i + 1 < size) {
                shell_printf(sh, "%c%c=",
                    b64[((buf[i] & 3) << 4) | (buf[i+1] >> 4)],
                    b64[((buf[i+1] & 0xF) << 2)]);
            } else {
                shell_printf(sh, "%c==", b64[(buf[i] & 3) << 4]);
            }
        }
        shell_printf(sh, "\n");
    } else {
        // Decode — simple base64 decoder
        // For now, just indicate decoding is iOS-only
        shell_printf(sh, "base64: decode requires iOS runtime\n");
    }

    free(buf);
    return 0;
}

int cmd_whoami(Shell *sh, int argc, char **argv) {
    (void)argc; (void)argv;
    shell_printf(sh, "mobile\n");
    return 0;
}

static time_t _app_start_time = 0;

int cmd_uptime(Shell *sh, int argc, char **argv) {
    (void)argc; (void)argv;
    if (_app_start_time == 0) _app_start_time = time(NULL);
    time_t now = time(NULL);
    long elapsed = (long)(now - _app_start_time);
    long hours = elapsed / 3600;
    long mins = (elapsed % 3600) / 60;
    long secs = elapsed % 60;
    shell_printf(sh, "up %ldh %ldm %lds\n", hours, mins, secs);
    return 0;
}

int cmd_open(Shell *sh, int argc, char **argv) {
    (void)argc; (void)argv;
    shell_printf(sh, "Use iOS Files app to open files in Safari.\n");
    shell_printf(sh, "Files location: On My iPhone > ClaudeShell\n");
    return 0;
}

int cmd_claude(Shell *sh, int argc, char **argv) {
    if (_claude_handler) {
        _claude_handler(sh, argc, argv);
        return sh->last_exit_code;
    }
    shell_printf(sh, "Claude AI — interactive mode handled by iOS app\n");
    shell_printf(sh, "Set your API key: export ANTHROPIC_API_KEY=sk-...\n");
    return 0;
}

// --- Main Dispatch Table ---

int cmd_dispatch(Shell *sh, int argc, char **argv) {
    if (argc == 0) return 0;
    const char *cmd = argv[0];

    // System
    if (strcmp(cmd, "echo") == 0) return cmd_echo(sh, argc, argv);
    if (strcmp(cmd, "env") == 0) return cmd_env(sh, argc, argv);
    if (strcmp(cmd, "which") == 0) return cmd_which(sh, argc, argv);
    if (strcmp(cmd, "clear") == 0) return cmd_clear(sh, argc, argv);
    if (strcmp(cmd, "exit") == 0) return cmd_exit(sh, argc, argv);
    if (strcmp(cmd, "help") == 0) return cmd_help(sh, argc, argv);
    if (strcmp(cmd, "date") == 0) return cmd_date(sh, argc, argv);
    if (strcmp(cmd, "sleep") == 0) return cmd_sleep(sh, argc, argv);
    if (strcmp(cmd, "true") == 0) return cmd_true_cmd(sh, argc, argv);
    if (strcmp(cmd, "false") == 0) return cmd_false_cmd(sh, argc, argv);
    if (strcmp(cmd, "test") == 0 || strcmp(cmd, "[") == 0) return cmd_test(sh, argc, argv);
    if (strcmp(cmd, "basename") == 0) return cmd_basename(sh, argc, argv);
    if (strcmp(cmd, "dirname") == 0) return cmd_dirname(sh, argc, argv);
    if (strcmp(cmd, "tee") == 0) return cmd_tee(sh, argc, argv);
    if (strcmp(cmd, "xargs") == 0) return cmd_xargs(sh, argc, argv);

    // Filesystem
    if (strcmp(cmd, "ls") == 0) return cmd_ls(sh, argc, argv);
    if (strcmp(cmd, "cat") == 0) return cmd_cat(sh, argc, argv);
    if (strcmp(cmd, "cp") == 0) return cmd_cp(sh, argc, argv);
    if (strcmp(cmd, "mv") == 0) return cmd_mv(sh, argc, argv);
    if (strcmp(cmd, "rm") == 0) return cmd_rm(sh, argc, argv);
    if (strcmp(cmd, "mkdir") == 0) return cmd_mkdir(sh, argc, argv);
    if (strcmp(cmd, "touch") == 0) return cmd_touch(sh, argc, argv);
    if (strcmp(cmd, "pwd") == 0) return cmd_pwd(sh, argc, argv);
    if (strcmp(cmd, "cd") == 0) return cmd_cd(sh, argc, argv);
    if (strcmp(cmd, "find") == 0) return cmd_find(sh, argc, argv);
    if (strcmp(cmd, "chmod") == 0) return cmd_chmod(sh, argc, argv);
    if (strcmp(cmd, "du") == 0) return cmd_du(sh, argc, argv);
    if (strcmp(cmd, "ln") == 0) return cmd_ln(sh, argc, argv);

    // Text
    if (strcmp(cmd, "grep") == 0) return cmd_grep(sh, argc, argv);
    if (strcmp(cmd, "head") == 0) return cmd_head(sh, argc, argv);
    if (strcmp(cmd, "tail") == 0) return cmd_tail(sh, argc, argv);
    if (strcmp(cmd, "wc") == 0) return cmd_wc(sh, argc, argv);
    if (strcmp(cmd, "sort") == 0) return cmd_sort(sh, argc, argv);
    if (strcmp(cmd, "uniq") == 0) return cmd_uniq(sh, argc, argv);
    if (strcmp(cmd, "sed") == 0) return cmd_sed(sh, argc, argv);
    if (strcmp(cmd, "tr") == 0) return cmd_tr(sh, argc, argv);
    if (strcmp(cmd, "cut") == 0) return cmd_cut(sh, argc, argv);
    if (strcmp(cmd, "diff") == 0) return cmd_diff(sh, argc, argv);

    // Network
    if (strcmp(cmd, "curl") == 0) return cmd_curl(sh, argc, argv);
    if (strcmp(cmd, "wget") == 0) return cmd_wget(sh, argc, argv);

    // Node.js / npm
    if (strcmp(cmd, "node") == 0) return cmd_node(sh, argc, argv);
    if (strcmp(cmd, "npm") == 0) return cmd_npm(sh, argc, argv);

    // Serve
    if (strcmp(cmd, "serve") == 0) return cmd_serve(sh, argc, argv);

    // Utility
    if (strcmp(cmd, "base64") == 0) return cmd_base64(sh, argc, argv);
    if (strcmp(cmd, "whoami") == 0) return cmd_whoami(sh, argc, argv);
    if (strcmp(cmd, "uptime") == 0) return cmd_uptime(sh, argc, argv);
    if (strcmp(cmd, "open") == 0) return cmd_open(sh, argc, argv);

    // Claude
    if (strcmp(cmd, "claude") == 0) return cmd_claude(sh, argc, argv);

    shell_printf(sh, "claudeshell: command not found: %s\n", cmd);
    return 127;
}
