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
    int start = 1;
    if (argc > 1 && strcmp(argv[1], "-n") == 0) { newline = 0; start = 2; }
    for (int i = start; i < argc; i++) {
        if (i > start) shell_printf(sh, " ");
        shell_printf(sh, "%s", argv[i]);
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
        "curl","wget","node","npm","claude", NULL
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
    shell_printf(sh, "\033[1mNetwork:\033[0m     curl wget\n");
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

    // Claude
    if (strcmp(cmd, "claude") == 0) return cmd_claude(sh, argc, argv);

    shell_printf(sh, "claudeshell: command not found: %s\n", cmd);
    return 127;
}
