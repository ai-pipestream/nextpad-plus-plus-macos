#import <Foundation/Foundation.h>
#import "SemanticProtocols.h"

NS_ASSUME_NONNULL_BEGIN

/// Exact (brute-force) in-memory vector index with a disk spill buffer.
///
/// Layout:
///   • HOT SET — one contiguous, GPU-friendly float buffer in RAM holding the
///     first vectors added after a reset (document order). Scored in a single
///     batched engine call.
///   • SPILL BUFFER — once the hot set would exceed its RAM budget, further
///     vectors are appended to a temp file on disk. At query time spilled
///     vectors are streamed back in fixed-size chunks through a reusable
///     scratch buffer and scored chunk-by-chunk with the same engine
///     (that is the reload path — nothing is permanently promoted in v1).
///
/// Threshold policy (documented in the .mm): the hot set is capped by BYTES,
/// not vector count, so the RAM budget is stable across embedding dimensions.
/// "Priority" is document order: earlier sentences stay hot, later ones spill.
/// A rebuild resets everything, so for the single-document v1 scope the spill
/// only engages on very large documents.
///
/// Scoring is exact over hot + spilled vectors, so results are identical to a
/// pure in-memory scan. Swap this class for an ANN implementation (turbovec…)
/// behind SemanticVectorIndex when scale demands it.
///
/// Not thread-safe: the heatmap controller confines it to one serial queue.
@interface SpillableVectorIndex : NSObject <SemanticVectorIndex>

/// engine performs the batched scoring (Metal/MPS or Accelerate).
- (instancetype)initWithSimilarityEngine:(id<SemanticSimilarityEngine>)engine;

/// Number of vectors currently living in the disk spill buffer (for status/tests).
@property (nonatomic, readonly) NSUInteger spilledCount;

@end

NS_ASSUME_NONNULL_END
