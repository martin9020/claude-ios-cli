#include "shell_helpers.h"
#include <string.h>

const char *shell_get_cwd(Shell *sh) {
    if (!sh) return "/";
    return sh->cwd;
}

const char *shell_get_root(Shell *sh) {
    if (!sh) return "/";
    return sh->root;
}

int shell_is_running(Shell *sh) {
    if (!sh) return 0;
    return sh->running;
}

void shell_set_exit_code(Shell *sh, int code) {
    if (!sh) return;
    sh->last_exit_code = code;
}

const char *shell_get_env(Shell *sh, const char *key) {
    return shell_getenv(sh, key);
}

void shell_output(Shell *sh, const char *text) {
    shell_printf(sh, "%s", text);
}

void shell_reset_running(Shell *sh) {
    if (!sh) return;
    sh->running = 1;
}
