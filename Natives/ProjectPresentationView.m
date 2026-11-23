#import "ProjectPresentationView.h"

@interface ProjectLayoutHandler : NSObject <WKScriptMessageHandler>
@property (nonatomic, copy) void (^update)(NSDictionary *message);
@end

@implementation ProjectLayoutHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (message.frameInfo.isMainFrame && [message.body isKindOfClass:NSDictionary.class]) self.update(message.body);
}
@end

@interface ProjectPresentationView () <WKNavigationDelegate>
@property (nonatomic) BOOL acceptedDocument;
@end

static NSString *ProjectResource(NSString *file) {
    NSURL *url = [NSBundle.mainBundle URLForResource:file withExtension:nil subdirectory:@"ProjectPage"];
    return url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
}

@implementation ProjectPresentationView

- (instancetype)initWithBody:(NSString *)body markdown:(BOOL)markdown baseURL:(NSURL *)baseURL
               heightChanged:(void (^)(void))heightChanged {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    configuration.defaultWebpagePreferences.allowsContentJavaScript = NO;
    WKContentWorld *world = WKContentWorld.defaultClientWorld;
    static NSString *renderer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        renderer = [@[ProjectResource(@"markdown-it.min.js") ?: @"", ProjectResource(@"purify.min.js") ?: @"",
                      ProjectResource(@"presentation.js") ?: @""] componentsJoinedByString:@"\n;\n"];
    });
    NSData *arguments = [NSJSONSerialization dataWithJSONObject:@[body, @(markdown)] options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:arguments encoding:NSUTF8StringEncoding];
    NSString *source = [renderer stringByAppendingFormat:@"\npresentProject(...%@);", json];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES inContentWorld:world];
    [configuration.userContentController addUserScript:script];
    ProjectLayoutHandler *handler = [[ProjectLayoutHandler alloc] init];
    [configuration.userContentController addScriptMessageHandler:handler contentWorld:world name:@"projectLayout"];
    self = [super initWithFrame:CGRectZero configuration:configuration];
    if (!self) return nil;
    self.navigationDelegate = self;
    self.opaque = NO;
    self.backgroundColor = UIColor.clearColor;
    self.scrollView.backgroundColor = UIColor.clearColor;
    self.scrollView.scrollEnabled = NO;
    NSLayoutConstraint *height = [self.heightAnchor constraintEqualToConstant:80];
    height.priority = UILayoutPriorityRequired - 1;
    height.active = YES;
    __weak typeof(self) weakView = self;
    __weak NSLayoutConstraint *weakHeight = height;
    handler.update = ^(NSDictionary *message) {
        ProjectPresentationView *view = weakView;
        if (!view) return;
        NSNumber *anchor = message[@"anchor"];
        if (anchor) {
            UIView *parent = view.superview;
            while (parent && ![parent isKindOfClass:UITableView.class]) parent = parent.superview;
            CGRect rect = [view convertRect:CGRectMake(0, anchor.doubleValue, 1, 32) toView:parent];
            [(UITableView *)parent scrollRectToVisible:rect animated:YES];
            return;
        }
        CGFloat value = [message[@"height"] doubleValue];
        if (isfinite(value) && value > 0 && weakHeight.constant != value) {
            weakHeight.constant = value;
            heightChanged();
        }
    };
    [self loadHTMLString:ProjectResource(@"presentation.html") baseURL:baseURL];
    return self;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
 decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    if (action.navigationType == WKNavigationTypeLinkActivated) {
        if ([@[@"https", @"http"] containsObject:url.scheme.lowercaseString]) {
            [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    BOOL initial = !self.acceptedDocument && action.navigationType == WKNavigationTypeOther && action.targetFrame.isMainFrame;
    if (initial) self.acceptedDocument = YES;
    decisionHandler(initial ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
@end
