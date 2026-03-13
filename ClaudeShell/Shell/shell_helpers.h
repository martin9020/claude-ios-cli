#ifndef SHELL_HELPERS_H
#define SHELL_HELPERS_H

#include "shell.h"

// Helper functions for Swift bridge — these provide safe access
// to Shell struct fields without needing .pointee on OpaquePointer.

// Get current working directory
const char *shell_get_cwd(Shell *sh);

// Get sandbox root
const char *shell_get_root(Shell *sh);

// Check if shell is still running
int shell_is_running(Shell *sh);

// Set last exit code
void shell_set_exit_code(Shell *sh, int code);

// Get environment variable (wrapper for shell_getenv)
const char *shell_get_env(Shell *sh, const char *key);

// Output a string through the shell's output callback
void shell_output(Shell *sh, const char *text);

#endif
