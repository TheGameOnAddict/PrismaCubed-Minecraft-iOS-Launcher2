#import <UIKit/UIKit.h>
@class DownloadTaskItem;

@interface CubicDownloadsController : UITableViewController
+ (void)showFrom:(UIViewController *)presenter task:(DownloadTaskItem *)task;
@end
