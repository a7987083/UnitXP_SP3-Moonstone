#import "ZNRangeControl.h"
#include <math.h>

@interface ZNRangeControl ()
@property(nonatomic,strong) UIView *maximumTrackView;
@property(nonatomic,strong) UIView *minimumTrackView;
@property(nonatomic,strong) UIView *thumbView;
@property(nonatomic,weak) UIScrollView *suspendedScrollView;
@property(nonatomic,assign) BOOL suspendedScrollWasEnabled;
@end

@implementation ZNRangeControl

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _minimumValue = 0.0;
    _maximumValue = 1.0;
    _value = 0.0;
    _maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:.18];
    _minimumTrackTintColor = UIColor.systemBlueColor;
    _thumbTintColor = UIColor.whiteColor;
    self.exclusiveTouch = YES;
    self.multipleTouchEnabled = NO;

    _maximumTrackView = [UIView new];
    _minimumTrackView = [UIView new];
    _thumbView = [UIView new];
    _maximumTrackView.userInteractionEnabled = NO;
    _minimumTrackView.userInteractionEnabled = NO;
    _thumbView.userInteractionEnabled = NO;
    [self addSubview:_maximumTrackView];
    [self addSubview:_minimumTrackView];
    [self addSubview:_thumbView];
    return self;
}

- (void)setMinimumTrackTintColor:(UIColor *)color { _minimumTrackTintColor = color; [self setNeedsLayout]; }
- (void)setMaximumTrackTintColor:(UIColor *)color { _maximumTrackTintColor = color; [self setNeedsLayout]; }
- (void)setThumbTintColor:(UIColor *)color { _thumbTintColor = color; [self setNeedsLayout]; }
- (void)setMinimumValue:(double)v { _minimumValue = isfinite(v) ? v : 0.0; if (_maximumValue <= _minimumValue) _maximumValue = _minimumValue + 1.0; self.value = _value; }
- (void)setMaximumValue:(double)v { _maximumValue = isfinite(v) ? v : (_minimumValue + 1.0); if (_maximumValue <= _minimumValue) _maximumValue = _minimumValue + 1.0; self.value = _value; }
- (void)setValue:(double)v {
    if (!isfinite(v)) v = _minimumValue;
    _value = MAX(_minimumValue, MIN(_maximumValue, v));
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds), h = CGRectGetHeight(self.bounds);
    CGFloat trackH = 4.0, thumb = MIN(22.0, MAX(16.0, h - 6.0));
    CGFloat usable = MAX(1.0, w - thumb);
    double span = MAX(1e-12, _maximumValue - _minimumValue);
    CGFloat t = (CGFloat)((_value - _minimumValue) / span);
    t = MAX(0.0, MIN(1.0, t));
    CGFloat cy = h * 0.5;
    CGFloat x = thumb * 0.5 + usable * t;

    _maximumTrackView.frame = CGRectMake(thumb * 0.5, cy - trackH * 0.5, usable, trackH);
    _maximumTrackView.backgroundColor = _maximumTrackTintColor;
    _maximumTrackView.layer.cornerRadius = trackH * 0.5;

    _minimumTrackView.frame = CGRectMake(thumb * 0.5, cy - trackH * 0.5, MAX(0.0, x - thumb * 0.5), trackH);
    _minimumTrackView.backgroundColor = _minimumTrackTintColor;
    _minimumTrackView.layer.cornerRadius = trackH * 0.5;

    _thumbView.frame = CGRectMake(x - thumb * 0.5, cy - thumb * 0.5, thumb, thumb);
    _thumbView.backgroundColor = _thumbTintColor;
    _thumbView.layer.cornerRadius = thumb * 0.5;
    _thumbView.layer.shadowColor = UIColor.blackColor.CGColor;
    _thumbView.layer.shadowOpacity = .28;
    _thumbView.layer.shadowRadius = 2.0;
    _thumbView.layer.shadowOffset = CGSizeMake(0, 1);
}

- (UIScrollView *)zn_parentScrollView {
    UIView *v = self.superview;
    while (v) {
        if ([v isKindOfClass:UIScrollView.class]) return (UIScrollView *)v;
        v = v.superview;
    }
    return nil;
}

- (void)zn_suspendScrollIfNeeded {
    if (self.suspendedScrollView) return;
    UIScrollView *scroll = [self zn_parentScrollView];
    if (!scroll) return;
    self.suspendedScrollView = scroll;
    self.suspendedScrollWasEnabled = scroll.scrollEnabled;
    scroll.scrollEnabled = NO;
}

- (void)zn_restoreScrollIfNeeded {
    UIScrollView *scroll = self.suspendedScrollView;
    if (scroll) scroll.scrollEnabled = self.suspendedScrollWasEnabled;
    self.suspendedScrollView = nil;
}

- (void)zn_updateFromTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self];
    CGFloat w = CGRectGetWidth(self.bounds), h = CGRectGetHeight(self.bounds);
    CGFloat thumb = MIN(22.0, MAX(16.0, h - 6.0));
    CGFloat usable = MAX(1.0, w - thumb);
    CGFloat normalized = (p.x - thumb * 0.5) / usable;
    normalized = MAX(0.0, MIN(1.0, normalized));
    self.value = self.minimumValue + (self.maximumValue - self.minimumValue) * normalized;
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    [self zn_suspendScrollIfNeeded];
    [self zn_updateFromTouch:touch];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    [self zn_updateFromTouch:touch];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    if (touch) [self zn_updateFromTouch:touch];
    [self zn_restoreScrollIfNeeded];
    [self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    (void)event;
    [self zn_restoreScrollIfNeeded];
}

@end
