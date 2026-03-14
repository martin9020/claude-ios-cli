// Bridging header — exposes C shell to Swift

#ifndef ClaudeShell_Bridging_Header_h
#define ClaudeShell_Bridging_Header_h

#include "../Shell/shell.h"
#include "../Shell/builtins.h"
#include "../Shell/environment.h"
#include "../Shell/shell_helpers.h"

// Network handler registration (from cmd_network.c)
typedef void (*network_request_fn)(Shell *sh, const char *url, const char *method,
                                    const char *data, const char *output_file);
void shell_set_network_handler(network_request_fn handler);

// Claude handler registration (from cmd_system.c)
typedef void (*claude_handler_fn)(Shell *sh, int argc, char **argv);
void shell_set_claude_handler(claude_handler_fn handler);

// Node/npm handler registration (from cmd_system.c)
typedef void (*node_handler_fn)(Shell *sh, int argc, char **argv);
void shell_set_node_handler(node_handler_fn handler);
void shell_set_npm_handler(node_handler_fn handler);

#endif
