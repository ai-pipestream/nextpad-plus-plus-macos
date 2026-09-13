#undef NDEBUG
#import "SpillableVectorIndex.h"
#include <cassert>
#include <vector>

@interface TestSimilarityEngine : NSObject <SemanticSimilarityEngine>
@property BOOL fail;
@end

@implementation TestSimilarityEngine
- (NSString *)engineName { return @"Test dot product"; }
- (BOOL)scoresForQuery:(const float *)query vectors:(const float *)vectors
                count:(NSUInteger)count dimension:(NSUInteger)dimension
            outScores:(float *)outScores {
    if (self.fail) return NO;
    for (NSUInteger row = 0; row < count; ++row) {
        outScores[row] = 0;
        for (NSUInteger col = 0; col < dimension; ++col)
            outScores[row] += query[col] * vectors[row * dimension + col];
    }
    return YES;
}
@end

int main() {
    @autoreleasepool {
        TestSimilarityEngine *engine = [TestSimilarityEngine new];
        SpillableVectorIndex *index = [[SpillableVectorIndex alloc] initWithSimilarityEngine:engine];
        [index resetWithDimension:512];
        std::vector<float> query(512, 0);
        query[0] = 1;
        std::vector<float> unrelated(512, 0);
        unrelated[1] = 1;
        // Cross the 16 MiB hot-set boundary and include a match on disk.
        for (int64_t i = 0; i < 8193; ++i)
            assert([index addVector:i == 8192 ? query.data() : unrelated.data() sentenceID:i + 100]);
        assert(index.count == 8193);
        assert(index.spilledCount == 1);
        std::vector<SemanticHit> hits(index.count);
        assert([index scoreAllForQuery:query.data() hits:hits.data() capacity:hits.size()] == hits.size());
        assert(hits.front().sentenceID == 100 && hits.front().score == 0);
        assert(hits.back().sentenceID == 8292 && hits.back().score == 1);
        SemanticHit best;
        assert([index search:query.data() k:1 hits:&best] == 1);
        assert(best.sentenceID == 8292 && best.score == 1);
        engine.fail = YES;
        assert([index scoreAllForQuery:query.data() hits:hits.data() capacity:hits.size()] == 0);
        assert([index search:query.data() k:1 hits:&best] == 0);
        [index resetWithDimension:3];
        assert(index.count == 0 && index.spilledCount == 0 && index.dimension == 3);
    }
}
