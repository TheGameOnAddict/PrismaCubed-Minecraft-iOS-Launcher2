#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Joins only measurements from this capture. Legacy reports have no ranked intervals.
FOUNDATION_EXPORT NSDictionary * _Nullable CubicHitchAnalysis(NSDictionary *report,
    NSDictionary * _Nullable javaSamples, NSDictionary * _Nullable jvmPauses);
FOUNDATION_EXPORT NSString *CubicHitchSummary(NSDictionary *analysis);

NS_ASSUME_NONNULL_END
