#import <Foundation/Foundation.h>
#import "SemanticProtocols.h"

NS_ASSUME_NONNULL_BEGIN

/// GPU similarity engine: batched dot products (== cosine on normalized
/// vectors) via MPSMatrixVectorMultiplication — scores = M(count×dim) · q.
/// Host-written MTLResourceStorageModeShared buffers; no private-storage
/// mirror is kept.
///
/// This is the ONLY engine the semantic heatmap ships: there is deliberately
/// no CPU fallback. When no Metal device supports MPS, +engineIfAvailable
/// returns nil and the feature fails loud — SemanticHeatmapController surfaces
/// "Metal GPU unavailable" in the search bar instead of silently degrading.
/// A different backend can still be swapped in through the
/// SemanticSimilarityEngine protocol.
@interface MetalSimilarityEngine : NSObject <SemanticSimilarityEngine>
+ (nullable instancetype)engineIfAvailable;
@end

NS_ASSUME_NONNULL_END
