#include "../Shell/builtins.h"
#include <errno.h>
#include <ctype.h>

static void resolve_path(Shell *sh, const char *input, char *output, size_t outsize) {
    if (input[0] == '/') snprintf(output, outsize, "%s%s", sh->root, input);
    else snprintf(output, outsize, "%s/%s", sh->cwd, input);
}

int cmd_grep(Shell *sh, int argc, char **argv) {
    if (argc < 3) {
        shell_printf(sh, "usage: grep [-i] [-n] [-c] [-v] pattern file [...]\n");
        return 1;
    }

    int case_insensitive = 0;
    int show_line_numbers = 0;
    int count_only = 0;
    int invert = 0;
    int opt_end = 1;

    while (opt_end < argc && argv[opt_end][0] == '-') {
        for (const char *f = argv[opt_end] + 1; *f; f++) {
            if (*f == 'i') case_insensitive = 1;
            else if (*f == 'n') show_line_numbers = 1;
            else if (*f == 'c') count_only = 1;
            else if (*f == 'v') invert = 1;
        }
        opt_end++;
    }

    if (opt_end + 1 >= argc) {
        shell_printf(sh, "usage: grep pattern file\n");
        return 1;
    }

    const char *pattern = argv[opt_end];

    int found_any = 0;
    for (int fi = opt_end + 1; fi < argc; fi++) {
        char path[SHELL_MAX_PATH];
        resolve_path(sh, argv[fi], path, sizeof(path));

        FILE *f = fopen(path, "r");
        if (!f) {
            shell_printf(sh, "grep: %s: %s\n", argv[fi], strerror(errno));
            continue;
        }

        char line[SHELL_MAX_LINE];
        int lineno = 0;
        int match_count = 0;

        while (fgets(line, sizeof(line), f)) {
            lineno++;
            int match = 0;

            if (case_insensitive) {
                char lower_line[SHELL_MAX_LINE], lower_pat[256];
                for (int i = 0; line[i]; i++)
                    lower_line[i] = tolower((unsigned char)line[i]);
                lower_line[strlen(line)] = '\0';
                for (int i = 0; pattern[i]; i++)
                    lower_pat[i] = tolower((unsigned char)pattern[i]);
                lower_pat[strlen(pattern)] = '\0';
                match = strstr(lower_line, lower_pat) != NULL;
            } else {
                match = strstr(line, pattern) != NULL;
            }

            if (invert) match = !match;

            if (match) {
                found_any = 1;
                match_count++;
                if (!count_only) {
                    if (show_line_numbers)
                        shell_printf(sh, "%d:", lineno);
                    shell_printf(sh, "%s", line);
                    if (line[strlen(line) - 1] != '\n')
                        shell_printf(sh, "\n");
                }
            }
        }

        if (count_only) {
            shell_printf(sh, "%d\n", match_count);
        }

        fclose(f);
    }

    return found_any ? 0 : 1;
}

int cmd_head(Shell *sh, int argc, char **argv) {
    int lines = 10;
    int file_arg = 1;

    if (argc >= 3 && strcmp(argv[1], "-n") == 0) {
        lines = atoi(argv[2]);
        file_arg = 3;
    } else if (argc >= 2 && argv[1][0] == '-' && isdigit((unsigned char)argv[1][1])) {
        lines = atoi(argv[1] + 1);
        file_arg = 2;
    }

    if (file_arg >= argc) {
        shell_printf(sh, "usage: head [-n N] file\n");
        return 1;
    }

    char path[SHELL_MAX_PATH];
    resolve_path(sh, argv[file_arg], path, sizeof(path));

    FILE *f = fopen(path, "r");
    if (!f) {
        shell_printf(sh, "head: %s: %s\n", argv[file_arg], strerror(errno));
        return 1;
    }

    char line[SHELL_MAX_LINE];
    int count = 0;
    while (count < lines && fgets(line, sizeof(line), f)) {
        shell_printf(sh, "%s", line);
        count++;
    }

    fclose(f);
    return 0;
}

int cmd_tail(Shell *sh, int argc, char **argv) {
    int lines = 10;
    int file_arg = 1;

    if (argc >= 3 && strcmp(argv[1], "-n") == 0) {
        lines = atoi(argv[2]);
        file_arg = 3;
    }

    if (file_arg >= argc) {
        shell_printf(sh, "usage: tail [-n N] file\n");
        return 1;
    }

    char path[SHELL_MAX_PATH];
    resolve_path(sh, argv[file_arg], path, sizeof(path));

    FILE *f = fopen(path, "r");
    if (!f) {
        shell_printf(sh, "tail: %s: %s\n", argv[file_arg], strerror(errno));
        return 1;
    }

    // Read all lines, keep last N
    char **buf = (char **)calloc(lines, sizeof(char *));
    char line[SHELL_MAX_LINE];
    int total = 0;

    while (fgets(line, sizeof(line), f)) {
        int idx = total % lines;
        free(buf[idx]);
        buf[idx] = strdup(line);
        total++;
    }

    int start = total > lines ? total - lines : 0;
    for (int i = start; i < total; i++) {
        shell_printf(sh, "%s", buf[i % lines]);
    }

    for (int i = 0; i < lines; i++) free(buf[i]);
    free(buf);
    fclose(f);
    return 0;
}

int cmd_wc(Shell *sh, int argc, char **argv) {
    if (argc < 2) {
        shell_printf(sh, "usage: wc [-l] [-w] [-c] file [...]\n");
        return 1;
    }

    int count_lines = 1, count_words = 1, count_bytes = 1;
    int file_start = 1;

    if (argv[1][0] == '-') {
        count_lines = count_words = count_bytes = 0;
        for (const char *f = argv[1] + 1; *f; f++) {
            if (*f == 'l') count_lines = 1;
            else if (*f == 'w') count_words = 1;
            else if (*f == 'c') count_bytes = 1;
        }
        file_start = 2;
    }

    for (int i = file_start; i < argc; i++) {
        char path[SHELL_MAX_PATH];
        resolve_path(sh, argv[i], path, sizeof(path));

        FILE *f = fopen(path, "r");
        if (!f) {
            shell_printf(sh, "wc: %s: %s\n", argv[i], strerror(errno));
            continue;
        }

        int lines = 0, words = 0, bytes = 0;
        int in_word = 0;
        int c;
        while ((c = fgetc(f)) != EOF) {
            bytes++;
            if (c == '\n') lines++;
            if (isspace(c)) { in_word = 0; }
            else if (!in_word) { in_word = 1; words++; }
        }

        if (count_lines) shell_printf(sh, "%7d ", lines);
        if (count_words) shell_printf(sh, "%7d ", words);
        if (count_bytes) shell_printf(sh, "%7d ", bytes);
        shell_printf(sh, "%s\n", argv[i]);

        fclose(f);
    }
    return 0;
}

int cmd_sort(Shell *sh, int argc, char **argv) {
    if (argc < 2) {
        shell_printf(sh, "usage: sort file\n");
        return 1;
    }

    int reverse = 0;
    int file_arg = 1;
    if (argc >= 2 && strcmp(argv[1], "-r") == 0) {
        reverse = 1;
        file_arg = 2;
    }

    if (file_arg >= argc) {
        shell_printf(sh, "usage: sort [-r] file\n");
        return 1;
    }

    char path[SHELL_MAX_PATH];
    resolve_path(sh, argv[file_arg], path, sizeof(path));

    FILE *f = fopen(path, "r");
    if (!f) {
        shell_printf(sh, "sort: %s: %s\n", argv[file_arg], strerror(errno));
        return 1;
    }

    // Read all lines
    char **lines = NULL;
    int count = 0, capacity = 0;
    char line[SHELL_MAX_LINE];

    while (fgets(line, sizeof(line), f)) {
        if (count >= capacity) {
            capacity = capacity ? capacity * 2 : 64;
            lines = (char **)realloc(lines, capacity * sizeof(char *));
        }
        lines[count++] = strdup(line);
    }
    fclose(f);

    // Bubble sort (simple, fine for small files)
    for (int i = 0; i < count - 1; i++) {
        for (int j = 0; j < count - i - 1; j++) {
            int cmp = strcmp(lines[j], lines[j + 1]);
            if (reverse ? cmp < 0 : cmp > 0) {
                char *tmp = lines[j];
                lines[j] = lines[j + 1];
                lines[j + 1] = tmp;
            }
        }
    }

    for (int i = 0; i < count; i++) {
        shell_printf(sh, "%s", lines[i]);
        free(lines[i]);
    }
    free(lines);
    return 0;
}

int cmd_uniq(Shell *sh, int argc, char **argv) {
    if (argc < 2) {
        shell_printf(sh, "usage: uniq [-c] [-d] file\n");
        return 1;
    }

    int show_count = 0;
    int only_dupes = 0;
    int file_arg = -1;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-c") == 0) show_count = 1;
        else if (strcmp(argv[i], "-d") == 0) only_dupes = 1;
        else file_arg = i;
    }

    if (file_arg < 0) {
        shell_printf(sh, "uniq: missing file argument\n");
        return 1;
    }

    char path[SHELL_MAX_PATH * 2];
    resolve_path(sh, argv[file_arg], path, sizeof(path));

    FILE *f = fopen(path, "r");
    if (!f) {
        shell_printf(sh, "uniq: %s: %s\n", argv[file_arg], strerror(errno));
        return 1;
    }

    char line[SHELL_MAX_LINE], prev[SHELL_MAX_LINE] = "";
    int count = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strcmp(line, prev) == 0) {
            count++;
        } else {
            if (prev[0] != '\0') {
                if (!only_dupes || count > 1) {
                    if (show_count)
                        shell_printf(sh, "%7d %s", count, prev);
                    else
                        shell_printf(sh, "%s", prev);
                }
            }
            strncpy(prev, line, sizeof(prev));
            count = 1;
        }
    }
    // Print last line
    if (prev[0] != '\0' && (!only_dupes || count > 1)) {
        if (show_count)
            shell_printf(sh, "%7d %s", count, prev);
        else
            shell_printf(sh, "%s", prev);
    }

    fclose(f);
    return 0;
}

int cmd_sed(Shell *sh, int argc, char **argv) {
    // Minimal sed: only supports s/pattern/replacement/[g]
    if (argc < 3) {
        shell_printf(sh, "usage: sed 's/pattern/replacement/[g]' file\n");
        return 1;
    }

    const char *expr = argv[1];
    if (expr[0] != 's' || expr[1] != '/') {
        shell_printf(sh, "sed: only s/pattern/replacement/ supported\n");
        return 1;
    }

    // Parse s/pattern/replacement/flags
    char pattern[256] = "", replacement[256] = "";
    int global = 0;

    const char *p = expr + 2;
    int pi = 0;
    while (*p && *p != '/' && pi < 255) pattern[pi++] = *p++;
    pattern[pi] = '\0';
    if (*p == '/') p++;

    pi = 0;
    while (*p && *p != '/' && pi < 255) replacement[pi++] = *p++;
    replacement[pi] = '\0';
    if (*p == '/') p++;
    if (*p == 'g') global = 1;

    char filepath[SHELL_MAX_PATH];
    resolve_path(sh, argv[2], filepath, sizeof(filepath));

    FILE *f = fopen(filepath, "r");
    if (!f) {
        shell_printf(sh, "sed: %s: %s\n", argv[2], strerror(errno));
        return 1;
    }

    char line[SHELL_MAX_LINE];
    while (fgets(line, sizeof(line), f)) {
        char result[SHELL_MAX_LINE];
        char *src = line;
        int ri = 0;
        int replaced = 0;

        while (*src && ri < SHELL_MAX_LINE - 1) {
            char *found = strstr(src, pattern);
            if (found && (!replaced || global)) {
                int prefix_len = (int)(found - src);
                memcpy(result + ri, src, prefix_len);
                ri += prefix_len;
                int rep_len = strlen(replacement);
                memcpy(result + ri, replacement, rep_len);
                ri += rep_len;
                src = found + strlen(pattern);
                replaced = 1;
            } else {
                result[ri++] = *src++;
            }
        }
        result[ri] = '\0';
        shell_printf(sh, "%s", result);
    }

    fclose(f);
    return 0;
}

int cmd_tr(Shell *sh, int argc, char **argv) {
    if (argc < 3) {
        shell_printf(sh, "usage: tr [-d] [-s] set1 [set2] [file]\n");
        return 1;
    }

    int delete_mode = 0;
    int squeeze_mode = 0;
    int opt_end = 1;

    for (int i = 1; i < argc && argv[i][0] == '-'; i++) {
        if (strcmp(argv[i], "-d") == 0) { delete_mode = 1; opt_end = i + 1; }
        else if (strcmp(argv[i], "-s") == 0) { squeeze_mode = 1; opt_end = i + 1; }
    }

    const char *set1 = (opt_end < argc) ? argv[opt_end] : "";
    // set2 only used for translate mode (not delete-only or squeeze-only)
    // In squeeze/delete mode, the arg after set1 is the input file (from pipe)
    int needs_set2 = !delete_mode && !squeeze_mode;
    const char *set2 = (needs_set2 && opt_end + 1 < argc) ? argv[opt_end + 1] : "";

    // Build translation table
    char map[256];
    for (int i = 0; i < 256; i++) map[i] = (char)i;

    // Expand ranges like a-z, A-Z, 0-9
    char expanded1[256] = "", expanded2[256] = "";
    int e1len = 0, e2len = 0;

    for (const char *p = set1; *p && e1len < 255; p++) {
        if (*(p+1) == '-' && *(p+2)) {
            char start = *p, end = *(p+2);
            for (char c = start; c <= end && e1len < 255; c++) expanded1[e1len++] = c;
            p += 2;
        } else {
            expanded1[e1len++] = *p;
        }
    }
    expanded1[e1len] = '\0';

    for (const char *p = set2; *p && e2len < 255; p++) {
        if (*(p+1) == '-' && *(p+2)) {
            char start = *p, end = *(p+2);
            for (char c = start; c <= end && e2len < 255; c++) expanded2[e2len++] = c;
            p += 2;
        } else {
            expanded2[e2len++] = *p;
        }
    }
    expanded2[e2len] = '\0';

    if (!delete_mode) {
        for (int i = 0; i < e1len; i++) {
            unsigned char from = (unsigned char)expanded1[i];
            char to = (i < e2len) ? expanded2[i] : (e2len > 0 ? expanded2[e2len - 1] : expanded1[i]);
            map[from] = to;
        }
    }

    // Find input file — last arg that isn't a flag or set argument
    // For -d and -s modes, only 1 set is needed; for translate, 2 sets
    int file_arg = -1;
    int sets_needed = (delete_mode || squeeze_mode) ? 1 : 2;
    int expected_args = opt_end + sets_needed;
    if (argc > expected_args) file_arg = argc - 1;

    FILE *f = NULL;
    if (file_arg >= 0) {
        char path[SHELL_MAX_PATH * 2];
        resolve_path(sh, argv[file_arg], path, sizeof(path));
        f = fopen(path, "r");
    }

    if (!f) {
        shell_printf(sh, "tr: no input\n");
        return 1;
    }

    char line[SHELL_MAX_LINE];
    char prev = 0;
    while (fgets(line, sizeof(line), f)) {
        for (int i = 0; line[i]; i++) {
            unsigned char c = (unsigned char)line[i];
            if (delete_mode) {
                if (!strchr(expanded1, (char)c)) {
                    shell_printf(sh, "%c", (char)c);
                    prev = (char)c;
                }
            } else {
                char out = map[c];
                if (squeeze_mode && out == prev && strchr(expanded1, (char)c)) continue;
                shell_printf(sh, "%c", out);
                prev = out;
            }
        }
    }

    fclose(f);
    return 0;
}

int cmd_cut(Shell *sh, int argc, char **argv) {
    if (argc < 3) {
        shell_printf(sh, "usage: cut -d<delim> -f<fields> [-c<range>] file\n");
        return 1;
    }

    char delim = '\t';
    int fields[32] = {0};
    int field_count = 0;
    int char_start = 0, char_end = 0;
    int char_mode = 0;
    int file_arg = -1;

    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "-d", 2) == 0) {
            // Handle: -d: (attached), -d ':' (next arg, quotes stripped)
            // Also -d':' where tokenizer keeps quotes: argv = [-d':']
            if (argv[i][2] != '\0') {
                char dc = argv[i][2];
                // Strip surrounding quotes if present: -d':' → skip ' to get :
                if ((dc == '\'' || dc == '"') && argv[i][3] != '\0') {
                    delim = argv[i][3];
                } else {
                    delim = dc;
                }
            } else if (i + 1 < argc) {
                delim = argv[++i][0];
            }
        } else if (strncmp(argv[i], "-f", 2) == 0) {
            // Handle -f2 or -f 2 or -f1,3
            const char *fval = argv[i][2] ? &argv[i][2] : (i + 1 < argc ? argv[++i] : "1");
            // Parse comma-separated field numbers
            const char *p = fval;
            while (*p && field_count < 32) {
                fields[field_count++] = atoi(p);
                while (*p && *p != ',') p++;
                if (*p == ',') p++;
            }
        } else if (strncmp(argv[i], "-c", 2) == 0) {
            char_mode = 1;
            const char *cval = argv[i][2] ? &argv[i][2] : (i + 1 < argc ? argv[++i] : "1");
            // Parse range like 1-3
            char_start = atoi(cval);
            const char *dash = strchr(cval, '-');
            char_end = dash ? atoi(dash + 1) : char_start;
        } else {
            file_arg = i;
        }
    }

    if (field_count == 0 && !char_mode) {
        fields[0] = 1;
        field_count = 1;
    }

    if (file_arg < 0) {
        shell_printf(sh, "cut: missing file argument\n");
        return 1;
    }

    char path[SHELL_MAX_PATH * 2];
    resolve_path(sh, argv[file_arg], path, sizeof(path));

    FILE *f = fopen(path, "r");
    if (!f) {
        shell_printf(sh, "cut: %s: %s\n", argv[file_arg], strerror(errno));
        return 1;
    }

    char line[SHELL_MAX_LINE];
    while (fgets(line, sizeof(line), f)) {
        // Remove trailing newline for processing
        int len = strlen(line);
        if (len > 0 && line[len - 1] == '\n') line[--len] = '\0';

        if (char_mode) {
            // Character range mode: -c1-3
            for (int i = char_start - 1; i < char_end && i < len; i++) {
                if (i >= 0) shell_printf(sh, "%c", line[i]);
            }
            shell_printf(sh, "\n");
        } else {
            // Field mode: split by delimiter
            char *tokens[256];
            int token_count = 0;
            char linecopy[SHELL_MAX_LINE];
            strncpy(linecopy, line, sizeof(linecopy) - 1);
            linecopy[sizeof(linecopy) - 1] = '\0';

            // Split into tokens
            char *p = linecopy;
            tokens[token_count++] = p;
            while (*p && token_count < 256) {
                if (*p == delim) {
                    *p = '\0';
                    tokens[token_count++] = p + 1;
                }
                p++;
            }

            // Output requested fields
            int first = 1;
            for (int fi = 0; fi < field_count; fi++) {
                int idx = fields[fi] - 1;
                if (idx >= 0 && idx < token_count) {
                    if (!first) shell_printf(sh, "%c", delim);
                    shell_printf(sh, "%s", tokens[idx]);
                    first = 0;
                }
            }
            shell_printf(sh, "\n");
        }
    }

    fclose(f);
    return 0;
}

int cmd_diff(Shell *sh, int argc, char **argv) {
    if (argc < 3) {
        shell_printf(sh, "usage: diff file1 file2\n");
        return 1;
    }

    char path1[SHELL_MAX_PATH], path2[SHELL_MAX_PATH];
    resolve_path(sh, argv[1], path1, sizeof(path1));
    resolve_path(sh, argv[2], path2, sizeof(path2));

    FILE *f1 = fopen(path1, "r");
    FILE *f2 = fopen(path2, "r");
    if (!f1 || !f2) {
        if (!f1) shell_printf(sh, "diff: %s: %s\n", argv[1], strerror(errno));
        if (!f2) shell_printf(sh, "diff: %s: %s\n", argv[2], strerror(errno));
        if (f1) fclose(f1);
        if (f2) fclose(f2);
        return 2;
    }

    char line1[SHELL_MAX_LINE], line2[SHELL_MAX_LINE];
    int lineno = 0;
    int differ = 0;

    while (1) {
        char *r1 = fgets(line1, sizeof(line1), f1);
        char *r2 = fgets(line2, sizeof(line2), f2);
        lineno++;

        if (!r1 && !r2) break;
        if (!r1) { shell_printf(sh, "%d: + %s", lineno, line2); differ = 1; continue; }
        if (!r2) { shell_printf(sh, "%d: - %s", lineno, line1); differ = 1; continue; }
        if (strcmp(line1, line2) != 0) {
            shell_printf(sh, "%d:\n< %s> %s", lineno, line1, line2);
            differ = 1;
        }
    }

    fclose(f1);
    fclose(f2);
    return differ ? 1 : 0;
}
