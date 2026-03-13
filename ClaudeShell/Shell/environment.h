#ifndef ENVIRONMENT_H
#define ENVIRONMENT_H

#include "shell.h"

const char *shell_getenv(Shell *sh, const char *key);
void shell_setenv(Shell *sh, const char *key, const char *val);
void shell_unsetenv(Shell *sh, const char *key);
void env_cleanup(Shell *sh);

#endif
