#ifndef NC_VERSION_COMPARE_H
#define NC_VERSION_COMPARE_H
// SemVer precedence; optional leading v/V, build metadata ignored.
// Returns 0 for malformed input, otherwise 1 with comparison -1 / 0 / 1.
int NCCompareVersions(const char *local, const char *remote, int *comparison);
#endif
