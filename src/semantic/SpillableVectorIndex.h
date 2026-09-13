#import <Foundation/Foundation.h>
#import "SemanticProtocols.h"

NS_ASSUME_NONNULL_BEGIN

/// Exact (brute-force) vector index: a contiguous in-RAM hot set plus a disk
/// spill buffer for overflow. Spill policy is documented in the .mm. Scoring
/// is exact over hot + spilled vectors.
///
/// Not thread-safe — callers confine it to one serial queue.
@interface SpillableVectorIndex : NSObject <SemanticVectorIndex>

/// engine performs the batched scoring for both the hot set and spilled chunks.
- (instancetype)initWithSimilarityEngine:(id<SemanticSimilarityEngine>)engine;

/// Number of vectors currently in the disk spill buffer.
@property (nonatomic, readonly) NSUInteger spilledCount;

@end

NS_ASSUME_NONNULL_END
