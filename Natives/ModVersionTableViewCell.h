#import <UIKit/UIKit.h>
#import "ModVersion.h"

NS_ASSUME_NONNULL_BEGIN

@interface ModVersionTableViewCell : UITableViewCell

- (instancetype)initWithProjectAccent:(UIColor *)accent cornerRadius:(CGFloat)radius reuseIdentifier:(NSString *)identifier;
- (void)configureWithVersion:(ModVersion *)version;

@end

NS_ASSUME_NONNULL_END
