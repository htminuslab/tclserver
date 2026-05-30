/*
 * ParseRTL.c — Mixed VHDL/SystemVerilog hierarchy extractor
 *
 * Scans a directory recursively for .vhd/.vhdl/.v/.sv/.svh/.vh files,
 * extracts entity/module definitions and instantiations, identifies the
 * testbench (top-level) and DUT, and reports the result as JSON.
 *
 * Build (GCC, Windows or Linux):
 *   gcc -O2 -Wall -o ParseRTL ParseRTL.c
 *
 * Usage:
 *   ParseRTL [options] <directory>
 *
 * Options:
 *   -t          Print the design hierarchy (with filenames) as JSON
 *   -u          Scope to the DUT instead of the whole testbench design
 *   -f [name]   Write the source files (compile order) to <name>
 *               (default: files.txt)
 *   -h          Show this help
 *
 * Output model:
 *   (default)        JSON summary: { "testbench": ..., "dut": ... }
 *   -u               JSON summary: { "dut": ... }
 *   -t               JSON hierarchy rooted at the testbench
 *   -t -u            JSON hierarchy rooted at the DUT
 *   -f name          Writes the full design file list (compile order) and
 *                    prints the default summary JSON
 *   -f name -u       Writes the DUT-only file list and prints { "dut": ... }
 *
 * The file list is written in compile order: a post-order traversal so
 * every module appears after all the modules it instantiates.  Children are
 * visited in instance-label order (U_0, U_1, ...).  Path separators are
 * normalised to forward slashes.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* ------------------------------------------------------------------ */
/* Platform portability                                                 */
/* ------------------------------------------------------------------ */

#ifdef _WIN32
#  include <windows.h>
#  define PATH_SEP '\\'
#else
#  include <dirent.h>
#  include <sys/stat.h>
#  define PATH_SEP '/'
#endif

/* ------------------------------------------------------------------ */
/* Tuneable limits                                                      */
/* ------------------------------------------------------------------ */

#define MAX_NAME      128
#define MAX_FPATH     1024
#define MAX_MODULES   4096
#define MAX_EDGES     16384
#define MAX_CHILDREN  512

/* ------------------------------------------------------------------ */
/* Data structures                                                      */
/* ------------------------------------------------------------------ */

typedef struct {
    char name[MAX_NAME];    /* entity / module name (lower-cased)   */
    char file[MAX_FPATH];   /* source file it was defined in         */
    int  instantiated;      /* set to 1 when seen as a child         */
} Module;

typedef struct {
    int  parent_idx;            /* index into modules[]              */
    int  child_idx;
    char label[MAX_NAME];       /* instance label (for ordering)     */
} Edge;

static Module  modules[MAX_MODULES];
static int     module_count = 0;

static Edge    edges[MAX_EDGES];
static int     edge_count = 0;

/* ------------------------------------------------------------------ */
/* Small string utilities                                              */
/* ------------------------------------------------------------------ */

static void str_lower(char *s)
{
    for (; *s; s++) *s = (char)tolower((unsigned char)*s);
}

static char *ltrim(char *s)
{
    while (*s && isspace((unsigned char)*s)) s++;
    return s;
}

static const char *ltrimc(const char *s)
{
    while (*s && isspace((unsigned char)*s)) s++;
    return s;
}

/* Copy at most maxlen chars of a word (stops at non-alnum/_). */
static int copy_word(const char *src, char *dst, int maxlen)
{
    int i = 0;
    while (i < maxlen - 1 && src[i] &&
           (isalnum((unsigned char)src[i]) || src[i] == '_'))
    {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
    return i;
}

/* ------------------------------------------------------------------ */
/* Module registry                                                      */
/* ------------------------------------------------------------------ */

static int find_module(const char *name)
{
    int i;
    for (i = 0; i < module_count; i++)
        if (strcmp(modules[i].name, name) == 0)
            return i;
    return -1;
}

static int add_module(const char *name, const char *file)
{
    int idx = find_module(name);
    if (idx >= 0) {
        /* If we previously only saw it as a forward ref, fill in the
           real file now that we have parsed its definition. */
        if (strcmp(modules[idx].file, "(forward ref)") == 0 &&
            strcmp(file, "(forward ref)") != 0)
            strncpy(modules[idx].file, file, MAX_FPATH - 1);
        return idx;
    }
    if (module_count >= MAX_MODULES) {
        fprintf(stderr, "Error: too many modules (limit %d)\n", MAX_MODULES);
        exit(1);
    }
    strncpy(modules[module_count].name, name, MAX_NAME - 1);
    strncpy(modules[module_count].file, file, MAX_FPATH - 1);
    modules[module_count].instantiated = 0;
    return module_count++;
}

/* Record a parent->child instantiation edge with its instance label. */
static void add_edge(int parent, int child, const char *label)
{
    int i;
    for (i = 0; i < edge_count; i++)
        if (edges[i].parent_idx == parent && edges[i].child_idx == child)
            return;                       /* avoid duplicate edges */
    if (edge_count >= MAX_EDGES) {
        fprintf(stderr, "Error: too many edges (limit %d)\n", MAX_EDGES);
        exit(1);
    }
    edges[edge_count].parent_idx = parent;
    edges[edge_count].child_idx  = child;
    snprintf(edges[edge_count].label, MAX_NAME, "%s", label ? label : "");
    edge_count++;
    modules[child].instantiated = 1;
}

/* ------------------------------------------------------------------ */
/* Comment stripping helpers                                            */
/* ------------------------------------------------------------------ */

static void strip_line_comment(char *line, int is_vhdl)
{
    char *p = line;
    while (*p) {
        if (is_vhdl && p[0] == '-' && p[1] == '-') { *p = '\0'; break; }
        if (!is_vhdl && p[0] == '/' && p[1] == '/') { *p = '\0'; break; }
        p++;
    }
}

/* Multi-line block-comment state, reset per file in parse_sv. */
static int in_block_comment = 0;

static void strip_block_comment(char *buf)
{
    char *r = buf, *w = buf;
    while (*r) {
        if (in_block_comment) {
            if (r[0] == '*' && r[1] == '/') { in_block_comment = 0; r += 2; }
            else r++;
        } else {
            if (r[0] == '/' && r[1] == '*') { in_block_comment = 1; r += 2; }
            else *w++ = *r++;
        }
    }
    *w = '\0';
}

/* ------------------------------------------------------------------ */
/* VHDL file parser                                                     */
/* ------------------------------------------------------------------ */

static void parse_vhdl(const char *filepath)
{
    FILE *fp = fopen(filepath, "r");
    if (!fp) { perror(filepath); return; }

    char  line[4096];
    char  work[4096];
    char  token[MAX_NAME];
    char  label[MAX_NAME];
    int   current_entity = -1;

    /* Track declared components so we don't mis-identify them. */
    char  components[MAX_CHILDREN][MAX_NAME];
    int   comp_count = 0;

    while (fgets(line, sizeof(line), fp)) {
        snprintf(work, sizeof(work), "%s", line);
        strip_line_comment(work, 1);
        char *p = ltrim(work);
        str_lower(p);

        /* --- entity <name> is ------------------------------------ */
        if (strncmp(p, "entity", 6) == 0 && isspace((unsigned char)p[6])) {
            char *q = ltrim(p + 7);
            int   n = copy_word(q, token, MAX_NAME);
            if (n > 0) {
                char *r = ltrim(q + n);
                if (strncmp(r, "is", 2) == 0 &&
                    (!r[2] || isspace((unsigned char)r[2])))
                {
                    current_entity = add_module(token, filepath);
                    comp_count = 0;
                }
            }
        }

        /* --- component <name> ------------------------------------- */
        else if (strncmp(p, "component", 9) == 0 &&
                 isspace((unsigned char)p[9]))
        {
            char *q = ltrim(p + 10);
            int   n = copy_word(q, token, MAX_NAME);
            if (n > 0 && comp_count < MAX_CHILDREN)
                snprintf(components[comp_count++], MAX_NAME, "%s", token);
        }

        /* --- instantiations --------------------------------------- */
        else if (current_entity >= 0) {
            char *colon = strchr(p, ':');
            if (colon) {
                /* the instance label is the word before the colon */
                copy_word(p, label, MAX_NAME);

                /*
                 * A real instance label is a plain identifier, never a
                 * reserved word.  Reject "FOR ALL : comp USE ENTITY ..."
                 * configuration specifications and similar constructs so
                 * they are not mistaken for instantiations.
                 */
                if (strcmp(label, "for")  == 0 || strcmp(label, "if")    == 0 ||
                    strcmp(label, "case") == 0 || strcmp(label, "while") == 0)
                    continue;

                char *after = ltrim(colon + 1);

                /* Form 1 — explicit entity keyword */
                if (strncmp(after, "entity", 6) == 0 &&
                    isspace((unsigned char)after[6]))
                {
                    char *q = ltrim(after + 7);
                    char *dot = strchr(q, '.');   /* skip library prefix */
                    if (dot) q = dot + 1;
                    int n = copy_word(q, token, MAX_NAME);
                    if (n > 0) {
                        int child = find_module(token);
                        if (child < 0)
                            child = add_module(token, "(forward ref)");
                        add_edge(current_entity, child, label);
                    }
                }
                /* Form 2 — component instantiation */
                else {
                    int n = copy_word(after, token, MAX_NAME);
                    if (n > 0) {
                        int is_comp = 0, i;
                        for (i = 0; i < comp_count; i++)
                            if (strcmp(components[i], token) == 0)
                                { is_comp = 1; break; }

                        if (!is_comp) {
                            char *r = ltrim(after + n);
                            if (strncmp(r, "port", 4) == 0 ||
                                strncmp(r, "generic", 7) == 0)
                                is_comp = 1;
                        }

                        if (is_comp) {
                            int child = find_module(token);
                            if (child < 0)
                                child = add_module(token, "(forward ref)");
                            add_edge(current_entity, child, label);
                        }
                    }
                }
            }
        }
    }

    fclose(fp);
}

/* ------------------------------------------------------------------ */
/* Verilog / SystemVerilog file parser                                  */
/* ------------------------------------------------------------------ */

static const char *sv_keywords[] = {
    "module","endmodule","input","output","inout","wire","reg","logic",
    "parameter","localparam","assign","always","initial","begin","end",
    "if","else","case","endcase","for","generate","endgenerate",
    "function","endfunction","task","endtask","integer","real","time",
    "posedge","negedge","typedef","struct","enum","interface",
    "endinterface","package","endpackage","import","export","always_ff",
    "always_comb","always_latch","unique","priority","modport",
    "clocking","endclocking","property","endproperty","sequence",
    "endsequence","assert","assume","cover","restrict","default",
    "void","bit","byte","shortint","int","longint","string","chandle",
    NULL
};

static int is_sv_keyword(const char *s)
{
    int i;
    for (i = 0; sv_keywords[i]; i++)
        if (strcmp(sv_keywords[i], s) == 0)
            return 1;
    return 0;
}

/* Skip a balanced parenthesis group starting at the opening '('. */
static const char *skip_parens(const char *p)
{
    int depth = 0;
    while (*p) {
        if (*p == '(') depth++;
        else if (*p == ')') { depth--; if (depth == 0) return p + 1; }
        p++;
    }
    return p;
}

static void parse_sv(const char *filepath)
{
    FILE *fp = fopen(filepath, "r");
    if (!fp) { perror(filepath); return; }

    char line[4096];
    char work[4096];
    char tok1[MAX_NAME], tok2[MAX_NAME];
    int  current_module = -1;
    in_block_comment = 0;

    while (fgets(line, sizeof(line), fp)) {
        snprintf(work, sizeof(work), "%s", line);
        strip_block_comment(work);
        strip_line_comment(work, 0);
        char *p = ltrim(work);

        char lower[4096];
        snprintf(lower, sizeof(lower), "%s", p);
        str_lower(lower);
        char *pl = lower;

        /* --- module <name> ---------------------------------------- */
        if (strncmp(pl, "module", 6) == 0 &&
            isspace((unsigned char)pl[6]))
        {
            char *q = ltrim(pl + 7);
            int   n = copy_word(q, tok1, MAX_NAME);
            if (n > 0)
                current_module = add_module(tok1, filepath);
        }

        /* --- endmodule -------------------------------------------- */
        else if (strncmp(pl, "endmodule", 9) == 0) {
            current_module = -1;
        }

        /* --- instantiation: type [#(...)] instance ( ... ) -------- */
        else if (current_module >= 0) {
            int n1 = copy_word(pl, tok1, MAX_NAME);
            if (n1 == 0 || is_sv_keyword(tok1)) continue;

            const char *after1 = ltrim(pl + n1);

            if (after1[0] == '#') {                 /* parameter override */
                after1++;
                after1 = ltrimc(after1);
                if (after1[0] == '(')
                    after1 = ltrimc(skip_parens(after1));
            }

            int n2 = copy_word(after1, tok2, MAX_NAME);
            if (n2 == 0) continue;

            const char *after2 = ltrimc(after1 + n2);
            if (after2[0] != '(') continue;    /* must be followed by '(' */
            if (is_sv_keyword(tok2)) continue;

            /* tok1 = module type, tok2 = instance label */
            int child = find_module(tok1);
            if (child < 0)
                child = add_module(tok1, "(forward ref)");
            add_edge(current_module, child, tok2);
        }
    }

    fclose(fp);
}

/* ------------------------------------------------------------------ */
/* File extension check + directory scan                                */
/* ------------------------------------------------------------------ */

static int is_vhdl_ext(const char *name)
{
    const char *dot = strrchr(name, '.');
    if (!dot) return 0;
    char ext[16]; strncpy(ext, dot, 15); ext[15] = '\0'; str_lower(ext);
    return strcmp(ext, ".vhd") == 0 || strcmp(ext, ".vhdl") == 0;
}

static int is_sv_ext(const char *name)
{
    const char *dot = strrchr(name, '.');
    if (!dot) return 0;
    char ext[16]; strncpy(ext, dot, 15); ext[15] = '\0'; str_lower(ext);
    return strcmp(ext, ".v")   == 0 ||
           strcmp(ext, ".sv")  == 0 ||
           strcmp(ext, ".svh") == 0 ||
           strcmp(ext, ".vh")  == 0;
}

static void parse_file(const char *fullpath, const char *name)
{
    if (is_vhdl_ext(name))    parse_vhdl(fullpath);
    else if (is_sv_ext(name)) parse_sv(fullpath);
}

#ifdef _WIN32

static void scan_directory(const char *dirpath)
{
    char pattern[MAX_FPATH];
    snprintf(pattern, sizeof(pattern), "%s\\*", dirpath);

    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE) {
        fprintf(stderr, "Warning: cannot open directory '%s'\n", dirpath);
        return;
    }
    do {
        if (strcmp(fd.cFileName, ".") == 0 ||
            strcmp(fd.cFileName, "..") == 0) continue;

        char fullpath[MAX_FPATH];
        snprintf(fullpath, sizeof(fullpath), "%s\\%s", dirpath, fd.cFileName);

        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
            scan_directory(fullpath);
        else
            parse_file(fullpath, fd.cFileName);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
}

#else /* POSIX */

static void scan_directory(const char *dirpath)
{
    DIR *dp = opendir(dirpath);
    if (!dp) { perror(dirpath); return; }

    struct dirent *de;
    while ((de = readdir(dp)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 ||
            strcmp(de->d_name, "..") == 0) continue;

        char fullpath[MAX_FPATH];
        snprintf(fullpath, sizeof(fullpath), "%s/%s", dirpath, de->d_name);

        struct stat st;
        if (stat(fullpath, &st) != 0) continue;

        if (S_ISDIR(st.st_mode))
            scan_directory(fullpath);
        else if (S_ISREG(st.st_mode))
            parse_file(fullpath, de->d_name);
    }
    closedir(dp);
}

#endif

/* ------------------------------------------------------------------ */
/* Graph queries                                                        */
/* ------------------------------------------------------------------ */

typedef struct { int idx; const char *label; } ChildRef;

static int cmp_childref(const void *a, const void *b)
{
    return strcmp(((const ChildRef *)a)->label,
                  ((const ChildRef *)b)->label);
}

/*
 * Direct children of `parent`, returned sorted by instance label so that
 * traversal order is deterministic (U_0, U_1, U_2, ...).
 */
static int get_children(int parent, int *child_indices, int max)
{
    ChildRef refs[MAX_CHILDREN];
    int count = 0, i;
    for (i = 0; i < edge_count && count < max; i++)
        if (edges[i].parent_idx == parent) {
            refs[count].idx   = edges[i].child_idx;
            refs[count].label = edges[i].label;
            count++;
        }
    qsort(refs, count, sizeof(ChildRef), cmp_childref);
    for (i = 0; i < count; i++)
        child_indices[i] = refs[i].idx;
    return count;
}

/* Count unique descendants reachable from `idx`. */
static int count_descendants(int idx, int *seen)
{
    int children[MAX_CHILDREN];
    int n = get_children(idx, children, MAX_CHILDREN);
    int total = 0, i;
    for (i = 0; i < n; i++) {
        int c = children[i];
        if (!seen[c]) {
            seen[c] = 1;
            total++;
            total += count_descendants(c, seen);
        }
    }
    return total;
}

/* Testbench = the never-instantiated module with the most descendants. */
static int find_testbench_idx(void)
{
    int i, best_idx = -1, best_count = -1;
    for (i = 0; i < module_count; i++) {
        if (modules[i].instantiated) continue;
        int seen[MAX_MODULES];
        memset(seen, 0, sizeof(int) * module_count);
        seen[i] = 1;
        int cnt = count_descendants(i, seen);
        if (cnt > best_count) { best_count = cnt; best_idx = i; }
    }
    return best_idx;
}

/* DUT = the direct child of the testbench with the most descendants. */
static int find_dut_idx(void)
{
    int tb = find_testbench_idx();
    if (tb < 0) return -1;

    int children[MAX_CHILDREN];
    int n = get_children(tb, children, MAX_CHILDREN);
    int best_idx = -1, best_count = -1, j;
    for (j = 0; j < n; j++) {
        int c = children[j];
        int seen[MAX_MODULES];
        memset(seen, 0, sizeof(int) * module_count);
        seen[c] = 1;
        int cnt = count_descendants(c, seen);
        if (cnt > best_count) { best_count = cnt; best_idx = c; }
    }
    return best_idx;
}

/* ------------------------------------------------------------------ */
/* JSON output                                                          */
/* ------------------------------------------------------------------ */

static void print_indent(int n)
{
    int i;
    for (i = 0; i < n; i++) printf("  ");
}

/* Emit a JSON string: backslashes become '/', quotes are escaped. */
static void emit_json_string(const char *s)
{
    putchar('"');
    for (; *s; s++) {
        char c = (*s == '\\') ? '/' : *s;
        if (c == '"') putchar('\\');
        putchar(c);
    }
    putchar('"');
}

/*
 * Recursively print one hierarchy node as JSON.  `onpath[]` marks the
 * current recursion stack so cyclic instantiations terminate.  Ends
 * without a trailing newline so the caller can place a separator.
 */
static void print_node(int idx, int indent, int *onpath)
{
    print_indent(indent);     printf("{\n");
    print_indent(indent + 1); printf("\"name\": ");
    emit_json_string(modules[idx].name); printf(",\n");
    print_indent(indent + 1); printf("\"file\": ");
    emit_json_string(modules[idx].file); printf(",\n");
    print_indent(indent + 1); printf("\"instances\": [");

    int children[MAX_CHILDREN];
    int n = onpath[idx] ? 0 : get_children(idx, children, MAX_CHILDREN);

    if (n == 0) {
        printf("]\n");
    } else {
        printf("\n");
        onpath[idx] = 1;
        int i;
        for (i = 0; i < n; i++) {
            print_node(children[i], indent + 2, onpath);
            printf(i == n - 1 ? "\n" : ",\n");
        }
        onpath[idx] = 0;
        print_indent(indent + 1); printf("]\n");
    }
    print_indent(indent); printf("}");
}

static void print_hierarchy(int root)
{
    if (root < 0) { printf("{}\n"); return; }
    int onpath[MAX_MODULES];
    memset(onpath, 0, sizeof(int) * module_count);
    print_node(root, 0, onpath);
    printf("\n");
}

/* Summary JSON: { "testbench": ..., "dut": ... } or just the DUT. */
static void print_summary(int include_testbench)
{
    int tb  = find_testbench_idx();
    int dut = find_dut_idx();

    printf("{\n");
    if (include_testbench) {
        printf("  \"testbench\": ");
        if (tb >= 0) emit_json_string(modules[tb].name); else printf("null");
        printf(",\n");
    }
    printf("  \"dut\": ");
    if (dut >= 0) emit_json_string(modules[dut].name); else printf("null");
    printf("\n}\n");
}

/* ------------------------------------------------------------------ */
/* File list (compile order)                                            */
/* ------------------------------------------------------------------ */

/*
 * Post-order traversal: a module's file is emitted only after every module
 * it instantiates, giving a valid bottom-up compile order.  Forward refs
 * (no resolved source file) and duplicates are skipped.
 */
static void collect_files(int idx, int *seen,
                          char files[][MAX_FPATH], int *nfiles)
{
    seen[idx] = 1;

    int children[MAX_CHILDREN];
    int n = get_children(idx, children, MAX_CHILDREN);
    int i;
    for (i = 0; i < n; i++)
        if (!seen[children[i]])
            collect_files(children[i], seen, files, nfiles);

    if (strcmp(modules[idx].file, "(forward ref)") != 0) {
        int dup = 0, k;
        for (k = 0; k < *nfiles; k++)
            if (strcmp(files[k], modules[idx].file) == 0) { dup = 1; break; }
        if (!dup && *nfiles < MAX_MODULES)
            snprintf(files[(*nfiles)++], MAX_FPATH, "%s", modules[idx].file);
    }
}

static void write_files(const char *outname, int root)
{
    if (root < 0) {
        fprintf(stderr, "No design root found — %s not written\n", outname);
        return;
    }

    static char files[MAX_MODULES][MAX_FPATH]; /* static: too big for stack */
    int  nfiles = 0;
    int  seen[MAX_MODULES];
    memset(seen, 0, sizeof(int) * module_count);
    collect_files(root, seen, files, &nfiles);

    FILE *fp = fopen(outname, "w");
    if (!fp) { perror(outname); return; }

    int i, k;
    for (i = 0; i < nfiles; i++) {
        char norm[MAX_FPATH];
        for (k = 0; files[i][k]; k++)
            norm[k] = (files[i][k] == '\\') ? '/' : files[i][k];
        norm[k] = '\0';
        fprintf(fp, "%s\n", norm);
    }
    fclose(fp);
}

/* ------------------------------------------------------------------ */
/* Entry point                                                          */
/* ------------------------------------------------------------------ */

static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s [options] <directory>\n"
        "Options:\n"
        "  -t          Print the design hierarchy (with filenames) as JSON\n"
        "  -u          Scope to the DUT instead of the whole testbench design\n"
        "  -f [name]   Write source files in compile order to <name>"
                       " (default: files.txt)\n"
        "  -h          Show this help\n",
        prog);
}

int main(int argc, char *argv[])
{
    int         opt_top   = 0;   /* -t */
    int         opt_dut   = 0;   /* -u */
    const char *opt_files = NULL;/* -f (NULL = not requested)         */
    const char *directory = NULL;
    int i;

    for (i = 1; i < argc; i++) {
        if (argv[i][0] == '-') {
            int j;
            for (j = 1; argv[i][j]; j++) {
                switch (argv[i][j]) {
                    case 't': opt_top = 1; break;
                    case 'u': opt_dut = 1; break;
                    case 'f':
                        if (argv[i][j + 1]) {
                            opt_files = &argv[i][j + 1];     /* -fname */
                        } else if (i + 1 < argc &&
                                   argv[i + 1][0] != '-' &&
                                   strchr(argv[i + 1], '.') != NULL) {
                            opt_files = argv[++i];           /* -f name */
                        } else {
                            opt_files = "files.txt";         /* default */
                        }
                        j = (int)strlen(argv[i]) - 1;
                        break;
                    case 'h': usage(argv[0]); return 0;
                    default:
                        fprintf(stderr, "Unknown option: -%c\n", argv[i][j]);
                        usage(argv[0]);
                        return 1;
                }
            }
        } else {
            if (directory) {
                fprintf(stderr, "Error: only one directory argument allowed\n");
                usage(argv[0]);
                return 1;
            }
            directory = argv[i];
        }
    }

    if (!directory) {
        fprintf(stderr, "Error: no directory specified\n");
        usage(argv[0]);
        return 1;
    }

    scan_directory(directory);

    if (module_count == 0) {
        fprintf(stderr, "No VHDL/SV modules found in '%s'\n", directory);
        return 1;
    }

    /* Root for hierarchy / file list: DUT when -u, else the testbench. */
    int root = opt_dut ? find_dut_idx() : find_testbench_idx();

    if (opt_top)
        print_hierarchy(root);
    else
        print_summary(!opt_dut);

    if (opt_files)
        write_files(opt_files, root);

    return 0;
}
