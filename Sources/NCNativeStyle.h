#import <UIKit/UIKit.h>

@interface NCNativeStyle : NSObject
@property(nonatomic, strong) UIColor *pageColor, *cardColor, *textColor, *titleColor, *secondaryColor, *arrowColor, *switchColor;
@property(nonatomic, strong) UIFont *rowFont, *titleFont, *secondaryFont, *valueFont;
@property(nonatomic, strong) UIImage *rowArrow, *backImage;
@property(nonatomic) CGFloat rowHeight, cardInset, textInset, trailingInset, cornerRadius, groupGap, navigationHeight, topGap, backLeading;
@property(nonatomic) CGSize backSize;
@property(nonatomic) CGSize switchSize;
@end

NCNativeStyle *NCCaptureNativeStyle(UIViewController *owner);
