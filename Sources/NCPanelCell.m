#import "NCPanelCell.h"
#include <math.h>

@interface NCPanelCell ()
@property(nonatomic, strong) UIView *card;
@property(nonatomic, strong) UIImageView *arrow;
@end

@implementation NCPanelCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier])) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.card = [UIView new]; self.card.layer.masksToBounds = YES;
        [self.contentView addSubview:self.card];
        _mainLabel = [UILabel new]; _subtitleLabel = [UILabel new]; _valueLabel = [UILabel new];
        _subtitleLabel.numberOfLines = 0; _valueLabel.textAlignment = NSTextAlignmentRight;
        self.arrow = [UIImageView new]; self.arrow.contentMode = UIViewContentModeScaleAspectFit;
        for (UIView *view in @[_mainLabel, _subtitleLabel, _valueLabel, self.arrow]) [self.card addSubview:view];
    }
    return self;
}
- (void)setToggle:(NCNativeToggle *)toggle {
    [_toggle removeFromSuperview]; _toggle = toggle;
    if (toggle) [self.card addSubview:toggle];
}
+ (CGFloat)heightForStyle:(NCNativeStyle *)style width:(CGFloat)width subtitle:(NSString *)subtitle {
    if (!subtitle.length) return style.rowHeight;
    CGFloat available = MAX(40, width - 2*style.cardInset - style.textInset - style.trailingInset - style.switchSize.width - 12);
    CGRect text = [subtitle boundingRectWithSize:CGSizeMake(available, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName:style.secondaryFont} context:nil];
    return MAX(style.rowHeight + 16, ceil(style.rowFont.lineHeight + 4 + text.size.height + 20));
}
- (void)layoutSubviews {
    [super layoutSubviews];
    NCNativeStyle *style = self.nativeStyle;
    if (!style || self.contentView.bounds.size.width <= 2*style.cardInset || self.contentView.bounds.size.height <= 0) return;
    self.card.frame = CGRectInset(self.contentView.bounds, style.cardInset, 0);
    self.card.backgroundColor = style.cardColor;
    self.card.layer.cornerRadius = style.cornerRadius;
    self.card.layer.maskedCorners = self.roundedCorners;
    CGFloat width = self.card.bounds.size.width, height = self.card.bounds.size.height;
    CGFloat right = width - style.trailingInset, textRight = right;
    self.mainLabel.font = style.rowFont;
    self.mainLabel.textColor = self.emphasizesTitle ? style.switchColor : style.textColor;
    self.subtitleLabel.font = style.secondaryFont;
    self.subtitleLabel.textColor = style.secondaryColor;
    self.valueLabel.font = style.valueFont;
    self.valueLabel.textColor = style.secondaryColor;
    if (self.toggle) {
        CGSize intrinsic = self.toggle.intrinsicContentSize;
        if (intrinsic.width <= 0 || intrinsic.height <= 0) intrinsic = style.switchSize;
        self.toggle.bounds = CGRectMake(0, 0, intrinsic.width, intrinsic.height);
        if (intrinsic.width > 0 && intrinsic.height > 0)
            self.toggle.transform = CGAffineTransformMakeScale(style.switchSize.width/intrinsic.width, style.switchSize.height/intrinsic.height);
        self.toggle.center = CGPointMake(right-style.switchSize.width/2, height/2);
        textRight -= style.switchSize.width + 12;
    }
    self.arrow.hidden = !self.showsArrow;
    if (self.showsArrow) {
        self.arrow.image = style.rowArrow ?: [UIImage systemImageNamed:@"chevron.right"];
        self.arrow.tintColor = style.arrowColor;
        self.arrow.frame = CGRectMake(right-12, (height-18)/2, 12, 18);
        textRight -= 24;
    }
    if (self.valueLabel.text.length) {
        CGFloat valueWidth = MIN([self.valueLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX,height)].width, width*0.44);
        self.valueLabel.frame = CGRectMake(textRight-valueWidth,0,valueWidth,height);
        textRight -= valueWidth + 12;
    } else self.valueLabel.frame = CGRectZero;
    CGFloat textWidth = MAX(0,textRight-style.textInset);
    if (self.subtitleLabel.text.length) {
        CGSize sub = [self.subtitleLabel sizeThatFits:CGSizeMake(textWidth,CGFLOAT_MAX)];
        CGFloat block = style.rowFont.lineHeight + 4 + sub.height;
        CGFloat y = (height-block)/2;
        self.mainLabel.frame = CGRectMake(style.textInset,y,textWidth,style.rowFont.lineHeight);
        self.subtitleLabel.frame = CGRectMake(style.textInset,y+style.rowFont.lineHeight+4,textWidth,sub.height);
    } else {
        self.mainLabel.frame = CGRectMake(style.textInset,0,textWidth,height);
        self.subtitleLabel.frame = CGRectZero;
    }
}
@end
