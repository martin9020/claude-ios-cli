// Network commands — these bridge to Swift's URLSession via callback
// Since we can't use libcurl directly in iOS sandbox easily,
// we call back into Swift which handles HTTP via URLSession.

#include "../Shell/builtins.h"

// These are implemented in Swift via ShellBridge and called back through function pointers.
// The C stubs here just signal to the Swift bridge.

// Callback type for network requests (set by Swift bridge)
typedef void (*network_request_fn)(Shell *sh, const char *url, const char *method,
                                    const char *data, const char *output_file);

static network_request_fn _network_handler = NULL;

void shell_set_network_handler(network_request_fn handler) {
    _network_handler = handler;
}

int cmd_curl(Shell *sh, int argc, char **argv) {
    if (argc < 2) {
        shell_printf(sh, "usage: curl [-X METHOD] [-d DATA] [-H HEADER] [-o FILE] [-s] URL\n");
        return 1;
    }

    const char *url = NULL;
    const char *method = "GET";
    const char *data = NULL;
    const char *output_file = NULL;
    int silent = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-X") == 0 && i + 1 < argc) {
            method = argv[++i];
        } else if (strcmp(argv[i], "-d") == 0 && i + 1 < argc) {
            data = argv[++i];
            if (strcmp(method, "GET") == 0) method = "POST";
        } else if (strcmp(argv[i], "-H") == 0 && i + 1 < argc) {
            // Headers handled in Swift bridge
            i++;
        } else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            output_file = argv[++i];
        } else if (strcmp(argv[i], "-s") == 0) {
            silent = 1;
        } else if (strcmp(argv[i], "-L") == 0) {
            // Follow redirects — default in URLSession
        } else if (argv[i][0] != '-') {
            url = argv[i];
        }
    }

    if (!url) {
        shell_printf(sh, "curl: no URL specified\n");
        return 1;
    }

    if (!silent) {
        shell_printf(sh, "* Requesting %s %s...\n", method, url);
    }

    if (_network_handler) {
        _network_handler(sh, url, method, data, output_file);
        return sh->last_exit_code;
    }

    shell_printf(sh, "curl: network handler not initialized\n");
    return 1;
}

int cmd_wget(Shell *sh, int argc, char **argv) {
    if (argc < 2) {
        shell_printf(sh, "usage: wget URL\n");
        return 1;
    }

    // Rewrite as curl -o
    const char *url = argv[argc - 1];
    const char *filename = strrchr(url, '/');
    filename = filename ? filename + 1 : "download";

    if (strlen(filename) == 0) filename = "index.html";

    shell_printf(sh, "Saving to: %s\n", filename);

    if (_network_handler) {
        _network_handler(sh, url, "GET", NULL, filename);
        return sh->last_exit_code;
    }

    shell_printf(sh, "wget: network handler not initialized\n");
    return 1;
}
