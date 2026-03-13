#include "environment.h"

const char *shell_getenv(Shell *sh, const char *key) {
    if (!sh || !key) return NULL;
    for (int i = 0; i < sh->env_count; i++) {
        if (strcmp(sh->env_keys[i], key) == 0) {
            return sh->env_vals[i];
        }
    }
    return NULL;
}

void shell_setenv(Shell *sh, const char *key, const char *val) {
    if (!sh || !key) return;

    // Update existing
    for (int i = 0; i < sh->env_count; i++) {
        if (strcmp(sh->env_keys[i], key) == 0) {
            free(sh->env_vals[i]);
            sh->env_vals[i] = strdup(val ? val : "");
            return;
        }
    }

    // Add new
    if (sh->env_count < SHELL_MAX_ENV) {
        sh->env_keys[sh->env_count] = strdup(key);
        sh->env_vals[sh->env_count] = strdup(val ? val : "");
        sh->env_count++;
    }
}

void shell_unsetenv(Shell *sh, const char *key) {
    if (!sh || !key) return;
    for (int i = 0; i < sh->env_count; i++) {
        if (strcmp(sh->env_keys[i], key) == 0) {
            free(sh->env_keys[i]);
            free(sh->env_vals[i]);
            // Shift remaining
            for (int j = i; j < sh->env_count - 1; j++) {
                sh->env_keys[j] = sh->env_keys[j + 1];
                sh->env_vals[j] = sh->env_vals[j + 1];
            }
            sh->env_count--;
            return;
        }
    }
}

void env_cleanup(Shell *sh) {
    if (!sh) return;
    for (int i = 0; i < sh->env_count; i++) {
        free(sh->env_keys[i]);
        free(sh->env_vals[i]);
    }
    sh->env_count = 0;
}
