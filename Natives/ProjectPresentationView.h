#import <WebKit/WebKit.h>

@interface ProjectPresentationView : WKWebView
- (instancetype)initWithBody:(NSString *)body markdown:(BOOL)markdown baseURL:(NSURL *)baseURL
               heightChanged:(void (^)(void))heightChanged;
@end
