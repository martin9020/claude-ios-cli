#include "../Shell/builtins.h"
#include <dirent.h>
#include <sys/stat.h>
#include <errno.h>
#include <time.h>
#ifdef _WIN32
#include <direct.h>
#include <io.h>
#define mkdir(path, mode) _mkdir(path)
#define access _access
#define F_OK 0
#else
#include <unistd.h>
#include <libgen.h>
#endif

// Resolve a path relative to the sandbox
static void resolve_path(Shell *sh, const char *input, char *output, size_t outsize) {
    if (input[0] == '/') {
        snprintf(output, outsize, "%s%s", sh->root, input);
    } else if (input[0] == '~') {
        snprintf(output, outsize, "%s%s", sh->root, input + 1);
    } else {
        snprintf(output, outsize, "%s/%s", sh->cwd, input);
    }
}

int cmd_pwd(Shell *sh, int argc, char **argv) {
    // Show path relative to sandbox root
    const char *display = sh->cwd + strlen(sh->root);
    if (!*display) display = "/";
    shell_printf(sh, "%s\n", display);
    return 0;
}

int cmd_cd(Shell *sh, int argc, char **argv) {
    char target[SHELL_MAX_PATH];

    if (argc < 2 || strcmp(argv[1], "~") == 0) {
        strncpy(target, sh->root, sizeof(target));
    } else if (strcmp(argv[1], "-") == 0) {
        const char *old = shell_getenv(sh, "OLDPWD");
        if (old) strncpy(target, old, sizeof(target));
        else { shell_printf(sh, "cd: OLDPWD not set\n"); return 1; }
    } else if (strcmp(argv[1], "..") == 0) {
        strncpy(target, sh->cwd, sizeof(target));
        char *last_slash = strrchr(target, '/');
        if (last_slash && last_slash != target) *last_slash = '\0';
        // Don't go above sandbox root
        if (strlen(target) < strlen(sh->root)) {
            strncpy(target, sh->root, sizeof(target));
        }
    } else {
        resolve_path(sh, argv[1], target, sizeof(target));
    }

    struct stat st;
    if (stat(target, &st) != 0) {
        shell_printf(sh, "cd: %s: No such file or directory\n", argv[1]);
        return 1;
    }
    if (!S_ISDIR(st.st_mode)) {
        shell_printf(sh, "cd: %s: Not a directory\n", argv[1]);
        return 1;
    }

    // Ensure we stay within sandbox
    if (strncmp(target, sh->root, strlen(sh->root)) != 0) {
        shell_printf(sh, "cd: permission denied (outside sandbox)\n");
        return 1;
    }

    shell_setenv(sh, "OLDPWD", sh->cwd);
    strncpy(sh->cwd, target, SHELL_MAX_PATH);
    shell_setenv(sh, "PWD", sh->cwd);
    return 0;
}

int cmd_ls(Shell *sh, int argc, char **argv) {
    int long_format = 0;
    int show_all = 0;
    const char *target = NULL;

    for (int i = 1; i < argc; i++) {
        if (argv[i][0] == '-') {
            for (const char *f = argv[i] + 1; *f; f++) {
                if (*f == 'l') long_format = 1;
                else if (*f == 'a') show_all = 1;
            }
        } else {
            target = argv[i];
        }
    }

    char path[SHELL_MAX_PATH];
    if (target) {
        resolve_path(sh, target, path, sizeof(path));
    } else {
        strncpy(path, sh->cwd, sizeof(path));
    }

    DIR *dir = opendir(path);
    if (!dir) {
        shell_printf(sh, "ls: cannot access '%s': %s\n",
                     target ? target : ".", strerror(errno));
        return 1;
    }

    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (!show_all && entry->d_name[0] == '.') continue;

        if (long_format) {
            char fullpath[SHELL_MAX_PATH * 2];
            snprintf(fullpath, sizeof(fullpath), "%s/%s", path, entry->d_name);
            struct stat st;
            if (stat(fullpath, &st) == 0) {
                char perms[11] = "----------";
                if (S_ISDIR(st.st_mode)) perms[0] = 'd';
                if (st.st_mode & S_IRUSR) perms[1] = 'r';
                if (st.st_mode & S_IWUSR) perms[2] = 'w';
                if (st.st_mode & S_IXUSR) perms[3] = 'x';
                if (st.st_mode & S_IRGRP) perms[4] = 'r';
                if (st.st_mode & S_IWGRP) perms[5] = 'w';
                if (st.st_mode & S_IXGRP) perms[6] = 'x';
                if (st.st_mode & S_IROTH) perms[7] = 'r';
                if (st.st_mode & S_IWOTH) perms[8] = 'w';
                if (st.st_mode & S_IXOTH) perms[9] = 'x';

                char timebuf[64];
                struct tm *tm = localtime(&st.st_mtime);
                strftime(timebuf, sizeof(timebuf), "%b %d %H:%M", tm);

                shell_printf(sh, "%s %4lld %s %s\n",
                             perms, (long long)st.st_size, timebuf, entry->d_name);
            } else {
                shell_printf(sh, "?????????? ???? ??? ?? ??:?? %s\n", entry->d_name);
            }
        } else {
            shell_printf(sh, "%s  ", entry->d_name);
        }
    }

    if (!long_format) shell_printf(sh, "\n");
    closedir(dir);
    return 0;
}

int cmd_cat(Shell *sh, int argc, char **argv) {
    if (argc < 2) {
        shell_printf(sh, "usage: cat file [...]\n");
        return 1;
    }

    for (int i = 1; i < argc; i++) {
        char path[SHELL_MAX_PATH];
        resolve_path(sh, argv[i], path, sizeof(path));

        FILE *f = fopen(path, "r");
        if (!f) {
            shell_printf(sh, "cat: %s: %s\n", argv[i], strerror(errno));
            return 1;
        }

        char buf[4096];
        size_t n;
        while ((n = fread(buf, 1, sizeof(buf) - 1, f)) > 0) {
            buf[n] = '\0';
            shell_printf(sh, "%s", buf);
        }
        fclose(f);
    }
    return 0;
}

int cmd_cp(Shell *sh, int argc, char **argv) {
    int src_start = 1;

    if (argc >= 2 && (strcmp(argv[1], "-r") == 0 || strcmp(argv[1], "-R") == 0)) {
        // recursive flag accepted for compatibility (single-file copy only for now)
        src_start = 2;
    }

    if (argc < src_start + 2) {
        shell_printf(sh, "usage: cp [-r] source dest\n");
        return 1;
    }

    char src[SHELL_MAX_PATH], dst[SHELL_MAX_PATH];
    resolve_path(sh, argv[src_start], src, sizeof(src));
    resolve_path(sh, argv[src_start + 1], dst, sizeof(dst));

    FILE *in = fopen(src, "rb");
    if (!in) {
        shell_printf(sh, "cp: %s: %s\n", argv[src_start], strerror(errno));
        return 1;
    }

    // If dst is a directory, append source filename
    struct stat st;
    if (stat(dst, &st) == 0 && S_ISDIR(st.st_mode)) {
        const char *fname = strrchr(argv[src_start], '/');
        fname = fname ? fname + 1 : argv[src_start];
        char tmp[SHELL_MAX_PATH * 2];
        snprintf(tmp, sizeof(tmp), "%s/%s", dst, fname);
        strncpy(dst, tmp, sizeof(dst) - 1);
        dst[sizeof(dst) - 1] = '\0';
    }

    FILE *out = fopen(dst, "wb");
    if (!out) {
        shell_printf(sh, "cp: %s: %s\n", argv[src_start + 1], strerror(errno));
        fclose(in);
        return 1;
    }

    char buf[8192];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
        fwrite(buf, 1, n, out);
    }

    fclose(in);
    fclose(out);
    return 0;
}

int cmd_mv(Shell *sh, int argc, char **argv) {
    if (argc < 3) {
        shell_printf(sh, "usage: mv source dest\n");
        return 1;
    }

    char src[SHELL_MAX_PATH], dst[SHELL_MAX_PATH];
    resolve_path(sh, argv[1], src, sizeof(src));
    resolve_path(sh, argv[2], dst, sizeof(dst));

    struct stat st;
    if (stat(dst, &st) == 0 && S_ISDIR(st.st_mode)) {
        const char *fname = strrchr(argv[1], '/');
        fname = fname ? fname + 1 : argv[1];
        char tmp[SHELL_MAX_PATH * 2];
        snprintf(tmp, sizeof(tmp), "%s/%s", dst, fname);
        strncpy(dst, tmp, sizeof(dst) - 1);
        dst[sizeof(dst) - 1] = '\0';
    }

    if (rename(src, dst) != 0) {
        shell_printf(sh, "mv: %s\n", strerror(errno));
        return 1;
    }
    return 0;
}

int cmd_rm(Shell *sh, int argc, char **argv) {
    int force = 0;

    int start = 1;
    for (int i = 1; i < argc; i++) {
        if (argv[i][0] == '-') {
            for (const char *f = argv[i] + 1; *f; f++) {
                // -r/-R accepted for compatibility (recursive delete handled by remove())
                if (*f == 'f') force = 1;
            }
            start = i + 1;
        }
    }

    if (start >= argc) {
        shell_printf(sh, "usage: rm [-rf] file [...]\n");
        return 1;
    }

    for (int i = start; i < argc; i++) {
        char path[SHELL_MAX_PATH];
        resolve_path(sh, argv[i], path, sizeof(path));

        // Safety: never delete sandbox root
        if (strcmp(path, sh->root) == 0) {
            shell_printf(sh, "rm: refusing to remove sandbox root\n");
            return 1;
        }

        if (remove(path) != 0) {
            if (!force) {
                shell_printf(sh, "rm: %s: %s\n", argv[i], strerror(errno));
                return 1;
            }
        }
    }
    return 0;
}

int cmd_mkdir(Shell *sh, int argc, char **argv) {
    int make_parents = 0;
    int start = 1;

    if (argc >= 2 && strcmp(argv[1], "-p") == 0) {
        make_parents = 1;
        start = 2;
    }

    if (start >= argc) {
        shell_printf(sh, "usage: mkdir [-p] directory [...]\n");
        return 1;
    }

    for (int i = start; i < argc; i++) {
        char path[SHELL_MAX_PATH];
        resolve_path(sh, argv[i], path, sizeof(path));

        if (make_parents) {
            // Create parent directories
            char tmp[SHELL_MAX_PATH];
            strncpy(tmp, path, sizeof(tmp));
            for (char *p = tmp + 1; *p; p++) {
                if (*p == '/') {
                    *p = '\0';
                    mkdir(tmp, 0755);
                    *p = '/';
                }
            }
        }

        if (mkdir(path, 0755) != 0 && !make_parents) {
            shell_printf(sh, "mkdir: %s: %s\n", argv[i], strerror(errno));
            return 1;
        }
    }
    return 0;
}

int cmd_touch(Shell *sh, int argc, char **argv) {
    if (argc < 2) {
        shell_printf(sh, "usage: touch file [...]\n");
        return 1;
    }

    for (int i = 1; i < argc; i++) {
        char path[SHELL_MAX_PATH];
        resolve_path(sh, argv[i], path, sizeof(path));

        FILE *f = fopen(path, "a");
        if (f) fclose(f);
        else {
            shell_printf(sh, "touch: %s: %s\n", argv[i], strerror(errno));
            return 1;
        }
    }
    return 0;
}

int cmd_find(Shell *sh, int argc, char **argv) {
    char search_path[SHELL_MAX_PATH];
    const char *name_pattern = NULL;

    if (argc < 2) {
        strncpy(search_path, sh->cwd, sizeof(search_path));
    } else {
        resolve_path(sh, argv[1], search_path, sizeof(search_path));
    }

    // Parse -name flag
    for (int i = 1; i < argc - 1; i++) {
        if (strcmp(argv[i], "-name") == 0) {
            name_pattern = argv[i + 1];
            break;
        }
    }

    DIR *dir = opendir(search_path);
    if (!dir) {
        shell_printf(sh, "find: %s: %s\n", argv[1] ? argv[1] : ".", strerror(errno));
        return 1;
    }

    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (entry->d_name[0] == '.') continue;

        if (name_pattern) {
            // Simple wildcard match (just * prefix/suffix)
            if (name_pattern[0] == '*') {
                const char *suffix = name_pattern + 1;
                size_t slen = strlen(suffix);
                size_t nlen = strlen(entry->d_name);
                if (nlen >= slen && strcmp(entry->d_name + nlen - slen, suffix) == 0) {
                    const char *rel = search_path + strlen(sh->root);
                    shell_printf(sh, "%s/%s\n", rel[0] ? rel : ".", entry->d_name);
                }
            } else if (strcmp(entry->d_name, name_pattern) == 0) {
                const char *rel = search_path + strlen(sh->root);
                shell_printf(sh, "%s/%s\n", rel[0] ? rel : ".", entry->d_name);
            }
        } else {
            const char *rel = search_path + strlen(sh->root);
            shell_printf(sh, "%s/%s\n", rel[0] ? rel : ".", entry->d_name);
        }
    }

    closedir(dir);
    return 0;
}

int cmd_chmod(Shell *sh, int argc, char **argv) {
    if (argc < 3) {
        shell_printf(sh, "usage: chmod mode file\n");
        return 1;
    }
    char path[SHELL_MAX_PATH];
    resolve_path(sh, argv[2], path, sizeof(path));
    mode_t mode = (mode_t)strtol(argv[1], NULL, 8);
    if (chmod(path, mode) != 0) {
        shell_printf(sh, "chmod: %s\n", strerror(errno));
        return 1;
    }
    return 0;
}

int cmd_du(Shell *sh, int argc, char **argv) {
    int human = 0;
    const char *target = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0) human = 1;
        else target = argv[i];
    }

    char path[SHELL_MAX_PATH * 2];
    if (target) resolve_path(sh, target, path, sizeof(path));
    else strncpy(path, sh->cwd, sizeof(path) - 1);

    struct stat st;
    if (stat(path, &st) != 0) {
        shell_printf(sh, "du: %s: %s\n", target ? target : ".", strerror(errno));
        return 1;
    }

    long long bytes = (long long)st.st_size;
    if (human) {
        if (bytes >= 1024 * 1024)
            shell_printf(sh, "%.1fM\t%s\n", bytes / (1024.0 * 1024.0), target ? target : ".");
        else if (bytes >= 1024)
            shell_printf(sh, "%.1fK\t%s\n", bytes / 1024.0, target ? target : ".");
        else
            shell_printf(sh, "%lldB\t%s\n", bytes, target ? target : ".");
    } else {
        shell_printf(sh, "%lld\t%s\n", bytes / 1024, target ? target : ".");
    }
    return 0;
}

int cmd_ln(Shell *sh, int argc, char **argv) {
    shell_printf(sh, "ln: symbolic links not supported in iOS sandbox\n");
    return 1;
}
