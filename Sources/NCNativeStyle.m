#import "NCNativeStyle.h"

@implementation NCNativeStyle
- (instancetype)init {
    if ((self = [super init])) {
        // Screenshot-derived fallbacks; live source views take precedence.
        self.pageColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark ?
                [UIColor colorWithRed:14/255.0 green:13/255.0 blue:19/255.0 alpha:1] :
                [UIColor colorWithWhite:0.96 alpha:1];
        }];
        self.cardColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark ?
                [UIColor colorWithRed:28/255.0 green:27/255.0 blue:33/255.0 alpha:1] : [UIColor whiteColor];
        }];
        self.textColor = [UIColor labelColor];
        self.titleColor = self.textColor;
        self.secondaryColor = [UIColor secondaryLabelColor];
        self.arrowColor = [UIColor tertiaryLabelColor];
        self.switchColor = [UIColor colorWithRed:1 green:58/255.0 blue:58/255.0 alpha:1];
        self.rowFont = [UIFont systemFontOfSize:15];
        self.titleFont = [UIFont systemFontOfSize:17];
        self.secondaryFont = [UIFont systemFontOfSize:12];
        self.valueFont = [UIFont systemFontOfSize:13];
        self.rowHeight = 48; self.cardInset = 16; self.textInset = 16; self.trailingInset = 16;
        self.cornerRadius = 8; self.groupGap = 16; self.navigationHeight = 48; self.topGap = 8;
        self.backLeading = 16; self.backSize = CGSizeMake(12, 22);
        self.switchSize = CGSizeMake(51, 31);
    }
    return self;
}
@end
