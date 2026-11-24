#import "CubicDiagnosticText.h"

static NSString *diagnosticString(NSData *data) {
    if (!data.length) return nil;
    const unsigned char *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        unsigned char c = bytes[i];
        if (c < 32 && c != '\n' && c != '\r' && c != '\t' && c != 27) return nil;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // Bounded log reads can end partway through a UTF-8 character.
    for (NSUInteger cut = 1; !text && cut <= 3 && cut < data.length; cut++) {
        text = [[NSString alloc] initWithBytes:bytes length:data.length-cut encoding:NSUTF8StringEncoding];
    }
    return text;
}

static NSRegularExpression *expression(NSString *pattern) {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
        options:NSRegularExpressionCaseInsensitive error:&error];
    NSCAssert(regex, @"Invalid diagnostics expression: %@", error.localizedDescription);
    return regex;
}

static BOOL matches(NSRegularExpression *regex, NSString *text) {
    return [regex firstMatchInString:text options:0 range:NSMakeRange(0,text.length)] != nil;
}

NSData *CubicRedactedDiagnosticData(NSData *bytes) {
    NSString *text = diagnosticString(bytes);
    if (!text) return nil;

    static NSRegularExpression *privateLine, *continuedSecret;
    static NSArray<NSRegularExpression *> *patterns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Drop credential-bearing lines in full. Values can be quoted, escaped,
        // or embedded inside JSON, JVM arguments and URL query strings.
        NSString *sensitive = @"(?:access[_-]?token|refresh[_-]?token|client[_-]?token|auth[_-]?token|identity[_-]?token|id[_-]?token|session[_-]?(?:id|token)|client[_-]?secret|password|api[_-]?key|authorization|cookie|(?:^|[^A-Z0-9])(?:token|secret|ticket|username|userhash|accountId|xuid)\"?\\s*[:=]|xbox[_-]?(?:token|user[_-]?hash)|userproperties|profileproperties|--(?:username|uuid|xuid|clientId|session|server)|\\b(?:msal|bearer)\\s+|XBL3\\.0\\s+x=)";
        NSString *privateMarkers = @"\\[chat\\]|\\[CHAT/(?:INFO|WARN)\\]|\\b(?:whispers to you|you whisper to)\\b|(?:connecting to|connected to|server (?:address|ip)|serverAddress|serverIp|server-ip|multiplayer address)\\s*[:=, ]|\\b(?:command line|jvm_args|java_command)\\s*:";
        privateLine = expression([NSString stringWithFormat:@"%@|%@",sensitive, privateMarkers]);
        continuedSecret = expression([sensitive stringByAppendingString:@"[\"']?\\s*[:=]?\\s*$"]);
        patterns = @[expression(@"(?:https?|wss?|ftp)://[^\\s<>\"']+"),
            expression(@"[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}"),
            expression(@"(?<=/Application/)[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}"),
            expression(@"(?<![0-9.])(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?::[0-9]+)?(?![0-9.])"),
            expression(@"(?<![A-Z0-9_:])(?=[0-9A-F:]*::)(?=[0-9A-F:]*[0-9A-F])(?:[0-9A-F]{0,4}:){2,7}[0-9A-F]{0,4}(?![A-Z0-9_:])"),
            expression(@"(?<![0-9A-F:])(?:[0-9A-F]{1,4}:){7}[0-9A-F]{1,4}(?![0-9A-F:])"),
            expression(@"\\beyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]+")];
    });

    NSMutableString *result = [NSMutableString stringWithCapacity:text.length];
    __block BOOL skipValue = NO;
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        if (skipValue) {
            if ([line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) skipValue = NO;
            return;
        }
        if (matches(privateLine,line)) {
            skipValue = matches(continuedSecret,line);
            [result appendString:@"[private log entry omitted]\n"];
            return;
        }
        NSString *value = line;
        for (NSRegularExpression *pattern in patterns) {
            value = [pattern stringByReplacingMatchesInString:value options:0
                range:NSMakeRange(0,value.length) withTemplate:@"[redacted]"];
        }
        [result appendFormat:@"%@\n",value];
    }];
    return [result dataUsingEncoding:NSUTF8StringEncoding];
}

NSData *CubicRedactedHotSpotData(NSData *bytes) {
    NSString *text = diagnosticString(bytes);
    if (!text) return nil;
    static NSRegularExpression *summary, *frame;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        summary = expression(@"^#\\s*(?:A fatal error|(?:SIG[A-Z]+|EXCEPTION_[A-Z_]+)\\b|Internal Error\\b|JRE version:|Java VM:|Problematic frame:|Native memory allocation|There is insufficient memory)");
        frame = expression(@"^(?:[CJjvV]|Vv)\\s+\\S");
    });
    NSMutableString *excerpt = [NSMutableString string];
    __block BOOL frames = NO, problemFrame = NO;
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        // Stop before any register dump, raw heap values, process environment
        // or command-line arguments. The signal line follows the Java frames.
        if ([line hasPrefix:@"Registers:"] || [line hasPrefix:@"Register to memory mapping:"] ||
            [line containsString:@"  P R O C E S S  "]) { *stop = YES; return; }
        BOOL keep = matches(summary,line) || [line hasPrefix:@"Time: "] ||
            [line hasPrefix:@"Current thread "] || [line hasPrefix:@"Current thread:"] ||
            [line hasPrefix:@"siginfo:"] || [line hasPrefix:@"Stack: ["];
        if (problemFrame && [line hasPrefix:@"# "]) keep |= matches(frame,[line substringFromIndex:2]);
        problemFrame = [line containsString:@"Problematic frame:"];
        if ([line hasPrefix:@"Native frames:"] || [line hasPrefix:@"Java frames:"]) {
            frames = YES;
            keep = YES;
        } else if (frames) {
            frames = matches(frame,line);
            keep |= frames;
        }
        if (keep) [excerpt appendFormat:@"%@\n",line];
    }];
    return CubicRedactedDiagnosticData([excerpt dataUsingEncoding:NSUTF8StringEncoding]);
}
