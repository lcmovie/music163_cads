#ifndef NC_HOME_POLICY_H
#define NC_HOME_POLICY_H

enum {
    NCHomePromotionLabel = 1,
    NCHomeYunbeiCash = 2,
    NCHomeAdType = 4
};

/* Only runtime metadata values, never song titles or static template source. */
unsigned NCHomeTextEvidence(const char *field, const char *value);
int NCHomeMusicResource(const char *type);

#endif
