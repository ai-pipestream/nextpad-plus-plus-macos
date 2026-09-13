#import <Foundation/Foundation.h>
#import "SemanticProtocols.h"

NS_ASSUME_NONNULL_BEGIN

/// GPU similarity engine: batched dot products (== cosine on normalized
/// vectors) via MPSMatrixVectorMultiplication, using host-written
/// MTLResourceStorageModeShared buffers.
///
/// This is the only shipped engine — no CPU fallback. When no Metal device
/// supports MPS, +engineIfAvailable returns nil and the feature surfaces
/// "Metal GPU unavailable" in the search bar rather than silently degrading.
@interface MetalSimilarityEngine : NSObject <SemanticSimilarityEngine>
+ (nullable instancetype)engineIfAvailable;
@end

NS_ASSUME_NONNULL_END
