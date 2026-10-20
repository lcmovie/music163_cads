#include "NCHomePolicy.h"
static int equal(const char *a, const char *b) {
    if (!a || !b) return 0;
    while (*a && *a == *b) { ++a; ++b; }
    return *a == *b;
}

static int contains(const char *text, const char *part) {
    for (; *text; ++text) {
        const char *a = text, *b = part;
        while (*a && *b && *a == *b) { ++a; ++b; }
        if (!*b) return 1;
    }
    return 0;
}

int NCHomeMusicResource(const char *type) {
    return equal(type, "song") || equal(type, "music") || equal(type, "playList") ||
           equal(type, "playlist") || equal(type, "album") || equal(type, "artist") ||
           equal(type, "mv") || equal(type, "djRadio") || equal(type, "djProgram");
}

unsigned NCHomeTextEvidence(const char *field, const char *value) {
    if (!field || !value) return 0;
    if (equal(field, "resourceType") || equal(field, "creativeType")) {
        if (equal(value, "ad") || equal(value, "AD") || equal(value, "advertisement")) return NCHomeAdType;
        return 0;
    }
    int adLabel = equal(field, "adTag") || equal(field, "adTagText") || equal(field, "adLabel");
    int text = adLabel || equal(field, "title") || equal(field, "text") || equal(field, "subTitle") ||
               equal(field, "subtitle") || equal(field, "showTitle") || equal(field, "label") ||
               equal(field, "tagText") || equal(field, "name");
    if (!text) return 0;
    if (equal(value, "运营推广") || (adLabel && equal(value, "广告"))) return NCHomePromotionLabel;
    /* A Yunbei entrance or an ordinary cash-themed song is insufficient. */
    if (contains(value, "云贝") && (contains(value, "现金红包") || contains(value, "领现金") || contains(value, "现金福利")))
        return NCHomeYunbeiCash;
    return 0;
}
