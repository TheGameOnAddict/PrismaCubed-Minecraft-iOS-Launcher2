#import "CubicBootBackdrop.h"
#import <QuartzCore/QuartzCore.h>

// An original 32-pixel stone tile. Render the small bitmap once and scale with
// nearest-neighbor sampling so the grain stays square at every display scale.
static UIImage *stoneTile(void) {
    static UIImage *tile;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(32, 32), YES, 1);
        uint32_t seed = 91217;
        for (int pass = 0; pass < 3; pass++) {
            int size = 4 >> pass;
            for (int y = 0; y < 32; y += size) {
                for (int x = 0; x < 32; x += size) {
                    seed = 1664525 * seed + 1013904223;
                    CGFloat grey = 0.10 + ((seed >> 24) % 21) / 100.0;
                    [[UIColor colorWithWhite:grey alpha:pass == 0 ? 1 : 0.30] setFill];
                    UIRectFillUsingBlendMode(CGRectMake(x,y,size,size), kCGBlendModeNormal);
                }
            }
        }
        tile = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return tile;
}

@implementation CubicBootBackdrop {
    CGSize _drawnSize;
    NSArray<CAShapeLayer *> *_veins;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        self.opaque = YES;
        self.contentMode = UIViewContentModeRedraw;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(motionChanged:)
            name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGContextDrawTiledImage(context, CGRectMake(0,0,96,96), stoneTile().CGImage);
    // Vignette keeps the profile and diagnostics legible in either orientation.
    CGFloat colors[] = {0,0,0,0.68, 0,0,0,0.08};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGContextDrawRadialGradient(context, gradient, center, 0, center,
        MAX(self.bounds.size.width, self.bounds.size.height)*0.55, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

- (void)motionChanged:(NSNotification *)note {
    _drawnSize = CGSizeZero;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (CGSizeEqualToSize(size, _drawnSize) || CGSizeEqualToSize(size, CGSizeZero)) return;
    _drawnSize = size;
    for (CALayer *layer in _veins) [layer removeFromSuperlayer];
    NSMutableArray *layers = [NSMutableArray array];
    // Points lie on a three-point grid. Branch roots are shared with their trunk.
    static const CGPoint veins[][8] = {
        {{0,.14},{.07,.18},{.11,.23},{.15,.24},{.20,.31},{.25,.34},{.29,.40}},
        {{.11,.23},{.12,.15},{.16,.13},{.17,.095}},
        {{.20,.31},{.17,.38},{.17,.43},{.14,.46}},
        {{1,.85},{.93,.83},{.90,.75},{.85,.74},{.83,.68},{.78,.65},{.73,.61}},
        {{.90,.75},{.91,.68},{.94,.65},{.95,.60}},
        {{.83,.68},{.80,.73},{.76,.75},{.75,.79}},
    };
    static const int lengths[] = {7,4,4,7,4,4};
    static const double delays[] = {0,.54,1.12,.15,.72,1.27};
    CFTimeInterval start = CACurrentMediaTime();
    for (int v = 0; v < 6; v++) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        CGPoint last = CGPointZero;
        for (int i = 0; i < lengths[v]; i++) {
            CGPoint unit = veins[v][i];
            CGPoint point = CGPointMake(round(unit.x*size.width/3)*3, round(unit.y*size.height/3)*3);
            if (!i) [path moveToPoint:point];
            else {
                int steps = MAX(1,(int)ceil(MAX(fabs(point.x-last.x),fabs(point.y-last.y))/9));
                for (int step = 1; step <= steps; step++) {
                    CGFloat t = (CGFloat)step/steps;
                    CGFloat x = round((last.x+(point.x-last.x)*t)/3)*3;
                    CGFloat y = round((last.y+(point.y-last.y)*t)/3)*3;
                    [path addLineToPoint:CGPointMake(x,path.currentPoint.y)];
                    [path addLineToPoint:CGPointMake(x,y)];
                }
            }
            last = point;
        }
        BOOL trunk = v % 3 == 0;
        CAShapeLayer *layer = [CAShapeLayer layer];
        layer.path = path.CGPath;
        layer.fillColor = nil;
        layer.strokeColor = [UIColor colorWithRed:1 green:trunk ? .49 : .36 blue:.13 alpha:trunk ? .87 : .65].CGColor;
        layer.lineWidth = trunk ? 3 : 1.5;
        [self.layer addSublayer:layer];
        [layers addObject:layer];
        if (!UIAccessibilityIsReduceMotionEnabled()) {
            CABasicAnimation *open = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
            open.fromValue = @0;
            open.toValue = @1;
            open.duration = trunk ? 2 : 0.85;
            open.beginTime = [layer convertTime:start fromLayer:nil] + delays[v];
            open.fillMode = kCAFillModeBackwards;
            [layer addAnimation:open forKey:@"branch"];
        }
    }
    _veins = layers;
}
@end

@implementation CubicBootOptionsLabel
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.textAlignment = NSTextAlignmentCenter;
        self.textColor = [UIColor colorWithRed:1 green:.82 blue:.69 alpha:1];
        self.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        self.numberOfLines = 2;
        self.adjustsFontSizeToFitWidth = YES;
        self.minimumScaleFactor = .82;
    }
    return self;
}
- (void)setJavaVersion:(NSString *)version heap:(NSString *)heap renderer:(NSString *)renderer {
    self.text = [NSString stringWithFormat:NSLocalizedString(@"cubic.boot.options",nil),
                 version ?: @"…", heap ?: @"…", renderer ?: @"…"];
}
@end
