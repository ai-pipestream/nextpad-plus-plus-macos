#import <Foundation/Foundation.h>
#import "SemanticProtocols.h"

NS_ASSUME_NONNULL_BEGIN

/// GPU similarity engine: batched dot products (== cosine on normalized
/// vectors) via MPSMatrixVectorMultiplication — scores = M(count×dim) · q.
/// Returns nil from +engineIfAvailable when no Metal device supports MPS
/// (callers then use AccelerateSimilarityEngine instead).
@interface MetalSimilarityEngine : NSObject <SemanticSimilarityEngine>
+ (nullable instancetype)engineIfAvailable;
@end

/// CPU fallback engine: single cblas_sgemv call through Accelerate/vecLib.
/// Always available.
@interface AccelerateSimilarityEngine : NSObject <SemanticSimilarityEngine>
@end

/// Best engine for this machine: Metal/MPS when supported, Accelerate otherwise.
id<SemanticSimilarityEngine> NppBestSimilarityEngine(void);

NS_ASSUME_NONNULL_END
