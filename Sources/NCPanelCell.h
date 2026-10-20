#import "NCNativeStyle.h"

@protocol NCNativeToggleContract <NSObject>
@property(nonatomic, getter=isOn) BOOL on;
@property(nonatomic, strong) UIColor *onTintColor;
@end
typedef UIControl<NCNativeToggleContract> NCNativeToggle;

@interface NCPanelCell : UITableViewCell
@property(nonatomic, strong) NCNativeStyle *nativeStyle;
@property(nonatomic, readonly) UILabel *mainLabel, *subtitleLabel, *valueLabel;
@property(nonatomic, strong) NCNativeToggle *toggle;
@property(nonatomic) BOOL showsArrow;
@property(nonatomic) BOOL emphasizesTitle;
@property(nonatomic) CACornerMask roundedCorners;
+ (CGFloat)heightForStyle:(NCNativeStyle *)style width:(CGFloat)width subtitle:(NSString *)subtitle;
@end
