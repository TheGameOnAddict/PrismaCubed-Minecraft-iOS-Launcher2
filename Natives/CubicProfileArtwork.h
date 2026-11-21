#pragma once
#import <UIKit/UIKit.h>

static inline UIImage *CubicProfileArtwork(NSDictionary *profile, NSString *name) {
    NSString *encoded = profile[@"icon"];
    if ([encoded isKindOfClass:NSString.class] && encoded.length) {
        if ([encoded hasPrefix:@"data:image/"]) {
            NSRange prefix = [encoded rangeOfString:@";base64,"];
            if (prefix.location != NSNotFound) encoded = [encoded substringFromIndex:NSMaxRange(prefix)];
        }
        NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        if (image) return image;
    }
    NSString *identity = profile[@"gameDir"];
    if (![identity isKindOfClass:NSString.class] || !identity.length) identity = name;
    uint32_t hash = 2166136261u;
    for (NSUInteger i = 0; i < identity.length; ++i) {
        hash = (hash ^ [identity characterAtIndex:i]) * 16777619u;
    }
    NSArray *covers = @[@"CubicProfileCover", @"CubicProfileCover1", @"CubicProfileCover2", @"CubicProfileCover3"];
    return [UIImage imageNamed:covers[hash % covers.count]];
}
