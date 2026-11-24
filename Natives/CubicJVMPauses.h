#import <Foundation/Foundation.h>

/// Creates the bounded HotSpot log only for a performance-test report.
FOUNDATION_EXPORT NSString * _Nullable CubicPrepareJVMPauseArgument(NSURL * _Nullable reportURL);

/// Read on the diagnostics worker. Event times are relative to the capture start.
FOUNDATION_EXPORT NSDictionary * _Nullable CubicReadJVMPauses(NSURL * _Nullable reportURL,
    double captureWindowStartEpochMs, double measuredSeconds);
