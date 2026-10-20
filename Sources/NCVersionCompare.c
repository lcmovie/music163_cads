#include "NCVersionCompare.h"
#include <stddef.h>

typedef struct { const char *p; size_t n; } NCSlice;
typedef struct { NCSlice core[3], pre; } NCVersion;
static int digit(char c) { return c >= '0' && c <= '9'; }
static int identifier(char c) {
    return digit(c) || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-';
}
static int identifiers(NCSlice slice, int prerelease) {
    size_t begin = 0;
    for (size_t i = 0; i <= slice.n; i++) {
        if (i < slice.n && slice.p[i] != '.') {
            if (!identifier(slice.p[i])) return 0;
            continue;
        }
        if (i == begin) return 0;
        int numeric = 1;
        for (size_t j = begin; j < i; j++) if (!digit(slice.p[j])) numeric = 0;
        if (prerelease && numeric && i - begin > 1 && slice.p[begin] == '0') return 0;
        begin = i + 1;
    }
    return 1;
}
static int parse(const char *s, NCVersion *v) {
    if (!s) return 0;
    size_t n = 0;
    while (s[n] && n <= 128) n++;
    if (!n || n > 128) return 0;
    size_t i = (s[0] == 'v' || s[0] == 'V') ? 1 : 0;
    for (unsigned part = 0; part < 3; part++) {
        size_t begin = i;
        while (i < n && digit(s[i])) i++;
        if (i == begin || (i - begin > 1 && s[begin] == '0')) return 0;
        v->core[part] = (NCSlice){s + begin, i - begin};
        if (part < 2 && (i == n || s[i++] != '.')) return 0;
    }
    v->pre = (NCSlice){NULL, 0};
    if (i < n && s[i] == '-') {
        size_t begin = ++i;
        while (i < n && s[i] != '+') i++;
        v->pre = (NCSlice){s + begin, i - begin};
        if (!identifiers(v->pre, 1)) return 0;
    }
    if (i < n && s[i] == '+') {
        size_t begin = ++i;
        if (!identifiers((NCSlice){s + begin, n - begin}, 0)) return 0;
        i = n;
    }
    return i == n;
}
static int lexical(NCSlice a, NCSlice b) {
    size_t n = a.n < b.n ? a.n : b.n;
    for (size_t i = 0; i < n; i++)
        if (a.p[i] != b.p[i]) return (unsigned char)a.p[i] < (unsigned char)b.p[i] ? -1 : 1;
    return (a.n > b.n) - (a.n < b.n);
}
static int number(NCSlice a, NCSlice b) {
    return a.n == b.n ? lexical(a, b) : ((a.n > b.n) ? 1 : -1);
}
static int isNumeric(NCSlice a) {
    for (size_t i = 0; i < a.n; i++) if (!digit(a.p[i])) return 0;
    return 1;
}
static NCSlice next(NCSlice pre, size_t *position) {
    size_t begin = *position;
    while (*position < pre.n && pre.p[*position] != '.') ++*position;
    NCSlice item = {pre.p + begin, *position - begin};
    if (*position < pre.n) ++*position;
    return item;
}
int NCCompareVersions(const char *local, const char *remote, int *comparison) {
    NCVersion a, b;
    if (!comparison || !parse(local, &a) || !parse(remote, &b)) return 0;
    for (unsigned i = 0; i < 3; i++) {
        int c = number(a.core[i], b.core[i]);
        if (c) { *comparison = c; return 1; }
    }
    if (!a.pre.n || !b.pre.n) {
        *comparison = (a.pre.n == 0) - (b.pre.n == 0);
        return 1;
    }
    size_t ai = 0, bi = 0;
    while (ai < a.pre.n && bi < b.pre.n) {
        NCSlice aa = next(a.pre, &ai), bb = next(b.pre, &bi);
        int an = isNumeric(aa), bn = isNumeric(bb);
        int c = an && bn ? number(aa, bb) : (an != bn ? (an ? -1 : 1) : lexical(aa, bb));
        if (c) { *comparison = c; return 1; }
    }
    *comparison = (ai < a.pre.n) - (bi < b.pre.n);
    return 1;
}
