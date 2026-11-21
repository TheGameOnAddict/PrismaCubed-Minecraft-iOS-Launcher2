#pragma once
#import <UIKit/UIKit.h>

static inline UIImage *CubicProfileArtwork(NSDictionary *profile) {
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
    return [UIImage imageNamed:@"CubicProfileCover"];
}
