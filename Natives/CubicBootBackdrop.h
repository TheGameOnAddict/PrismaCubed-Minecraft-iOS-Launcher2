#import <UIKit/UIKit.h>

@interface CubicBootBackdrop : UIView
@end

@interface CubicBootOptionsLabel : UILabel
- (void)setJavaVersion:(NSString *)version heap:(NSString *)heap renderer:(NSString *)renderer;
@end
