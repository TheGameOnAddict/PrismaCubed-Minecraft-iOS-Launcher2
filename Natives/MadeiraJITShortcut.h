#import <Foundation/Foundation.h>

static inline NSURL *MadeiraJITShortcutImportURL(void) {
    return [NSURL URLWithString:@"https://www.icloud.com/shortcuts/878629f2925e45daa75301fbada5c892"];
}

static inline NSURL *MadeiraJITShortcutRunURL(NSString *input) {
    NSURLComponents *url = [NSURLComponents componentsWithString:@"shortcuts://run-shortcut"];
    url.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"name" value:@"Madeira JIT"],
        [NSURLQueryItem queryItemWithName:@"input" value:@"text"],
        [NSURLQueryItem queryItemWithName:@"text" value:input],
    ];
    return url.URL;
}
