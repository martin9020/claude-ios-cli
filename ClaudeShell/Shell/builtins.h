#ifndef BUILTINS_H
#define BUILTINS_H

#include "shell.h"

// Command dispatch — routes to the right handler
int cmd_dispatch(Shell *sh, int argc, char **argv);

// Filesystem commands
int cmd_ls(Shell *sh, int argc, char **argv);
int cmd_cat(Shell *sh, int argc, char **argv);
int cmd_cp(Shell *sh, int argc, char **argv);
int cmd_mv(Shell *sh, int argc, char **argv);
int cmd_rm(Shell *sh, int argc, char **argv);
int cmd_mkdir(Shell *sh, int argc, char **argv);
int cmd_touch(Shell *sh, int argc, char **argv);
int cmd_pwd(Shell *sh, int argc, char **argv);
int cmd_cd(Shell *sh, int argc, char **argv);
int cmd_find(Shell *sh, int argc, char **argv);
int cmd_chmod(Shell *sh, int argc, char **argv);
int cmd_du(Shell *sh, int argc, char **argv);
int cmd_ln(Shell *sh, int argc, char **argv);

// Text processing
int cmd_grep(Shell *sh, int argc, char **argv);
int cmd_head(Shell *sh, int argc, char **argv);
int cmd_tail(Shell *sh, int argc, char **argv);
int cmd_wc(Shell *sh, int argc, char **argv);
int cmd_sort(Shell *sh, int argc, char **argv);
int cmd_uniq(Shell *sh, int argc, char **argv);
int cmd_sed(Shell *sh, int argc, char **argv);
int cmd_tr(Shell *sh, int argc, char **argv);
int cmd_cut(Shell *sh, int argc, char **argv);
int cmd_diff(Shell *sh, int argc, char **argv);

// System commands
int cmd_echo(Shell *sh, int argc, char **argv);
int cmd_env(Shell *sh, int argc, char **argv);
int cmd_which(Shell *sh, int argc, char **argv);
int cmd_clear(Shell *sh, int argc, char **argv);
int cmd_exit(Shell *sh, int argc, char **argv);
int cmd_help(Shell *sh, int argc, char **argv);
int cmd_date(Shell *sh, int argc, char **argv);
int cmd_sleep(Shell *sh, int argc, char **argv);
int cmd_true_cmd(Shell *sh, int argc, char **argv);
int cmd_false_cmd(Shell *sh, int argc, char **argv);
int cmd_test(Shell *sh, int argc, char **argv);
int cmd_xargs(Shell *sh, int argc, char **argv);
int cmd_tee(Shell *sh, int argc, char **argv);
int cmd_basename(Shell *sh, int argc, char **argv);
int cmd_dirname(Shell *sh, int argc, char **argv);

// Network commands
int cmd_curl(Shell *sh, int argc, char **argv);
int cmd_wget(Shell *sh, int argc, char **argv);

// Claude commands
int cmd_claude(Shell *sh, int argc, char **argv);

// Node.js / npm commands
int cmd_node(Shell *sh, int argc, char **argv);
int cmd_npm(Shell *sh, int argc, char **argv);

// HTTP server
int cmd_serve(Shell *sh, int argc, char **argv);

// Utility commands
int cmd_base64(Shell *sh, int argc, char **argv);
int cmd_whoami(Shell *sh, int argc, char **argv);
int cmd_uptime(Shell *sh, int argc, char **argv);
int cmd_open(Shell *sh, int argc, char **argv);

#endif
