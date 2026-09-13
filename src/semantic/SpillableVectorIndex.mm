#import "SpillableVectorIndex.h"
#include <algorithm>
#include <cstring>
#include <vector>

// Spill policy: the hot set is capped by bytes (16 MB ≈ 8k vectors at dim 512)
// so the RAM budget is independent of embedding dimension. Vectors are hot in
// insertion (document) order; overflow appends to a temp file removed on
// dealloc. At query time spilled vectors stream back through a fixed 2 MB
// chunk and are scored with the same batched engine as the hot set, keeping
// peak memory bounded and results exact.
static const NSUInteger kHotSetMaxBytes     = 16u * 1024u * 1024u;
static const NSUInteger kSpillChunkMaxBytes =  2u * 1024u * 1024u;

@implementation SpillableVectorIndex {
    id<SemanticSimilarityEngine> _engine;
    NSUInteger _dimension;

    // Hot set: contiguous row-major float buffer + parallel id array.
    std::vector<float>   _hot;      // hotCount × dimension floats
    std::vector<int64_t> _ids;      // ids for ALL vectors, hot first then spilled
    NSUInteger _hotCapacityVectors; // derived from kHotSetMaxBytes at reset

    // Spill buffer: raw float rows appended to a temp file.
    NSString     *_spillPath;
    NSFileHandle *_spillWrite;      // nil until first spill
    NSUInteger    _spilledCount;
}

- (instancetype)initWithSimilarityEngine:(id<SemanticSimilarityEngine>)engine {
    self = [super init];
    if (!self) return nil;
    _engine = engine;
    return self;
}

- (void)dealloc {
    [self closeSpillFileAndUnlink];
}

- (NSUInteger)dimension    { return _dimension; }
- (NSUInteger)count        { return _ids.size(); }
- (NSUInteger)spilledCount { return _spilledCount; }

- (void)resetWithDimension:(NSUInteger)dimension {
    _dimension = dimension;
    _hot.clear();
    _ids.clear();
    _hotCapacityVectors = dimension ? kHotSetMaxBytes / (dimension * sizeof(float)) : 0;
    [self closeSpillFileAndUnlink];
    _spilledCount = 0;
}

- (BOOL)addVector:(const float *)vector sentenceID:(int64_t)sentenceID {
    if (_dimension == 0 || !vector) return NO;

    NSUInteger hotCount = _hot.size() / _dimension;
    if (hotCount < _hotCapacityVectors) {
        _hot.insert(_hot.end(), vector, vector + _dimension);
    } else {
        if (![self appendToSpill:vector]) return NO;
        _spilledCount++;
    }
    _ids.push_back(sentenceID);
    return YES;
}

- (NSUInteger)scoreAllForQuery:(const float *)query
                          hits:(SemanticHit *)hits
                      capacity:(NSUInteger)capacity {
    if (_dimension == 0 || _ids.empty() || !query || !hits) return 0;

    const NSUInteger total = _ids.size();
    std::vector<float> scores(total, 0.0f);

    // 1) Hot set: one batched engine call over the contiguous RAM buffer.
    const NSUInteger hotCount = _hot.size() / _dimension;
    if (hotCount > 0) {
        if (![_engine scoresForQuery:query vectors:_hot.data()
                               count:hotCount dimension:_dimension
                           outScores:scores.data()])
            return 0;
    }

    // 2) Spill buffer: stream chunks from disk through a scratch buffer.
    if (_spilledCount > 0 && ![self scoreSpilledForQuery:query
                                               intoScores:scores.data() + hotCount])
        return 0;

    NSUInteger n = std::min((NSUInteger)total, capacity);
    for (NSUInteger i = 0; i < n; i++)
        hits[i] = SemanticHit{ _ids[i], scores[i] };
    return n;
}

- (NSUInteger)search:(const float *)query k:(NSUInteger)k hits:(SemanticHit *)hits {
    if (k == 0 || _ids.empty() || !query || !hits) return 0;
    std::vector<SemanticHit> all(_ids.size());
    NSUInteger n = [self scoreAllForQuery:query hits:all.data() capacity:all.size()];
    if (n == 0) return 0;
    NSUInteger topK = std::min((NSUInteger)n, k);
    std::partial_sort(all.begin(), all.begin() + topK, all.begin() + n,
                      [](const SemanticHit &a, const SemanticHit &b) {
                          return a.score > b.score;
                      });
    memcpy(hits, all.data(), topK * sizeof(SemanticHit));
    return topK;
}

#pragma mark - Spill buffer internals

- (BOOL)appendToSpill:(const float *)vector {
    if (!_spillWrite) {
        NSString *name = [NSString stringWithFormat:@"npp-semantic-spill-%@.vec",
                                                    NSUUID.UUID.UUIDString];
        _spillPath = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        if (![[NSFileManager defaultManager] createFileAtPath:_spillPath
                                                     contents:nil attributes:nil])
            return NO;
        _spillWrite = [NSFileHandle fileHandleForWritingAtPath:_spillPath];
        if (!_spillWrite) return NO;
    }
    NSData *row = [NSData dataWithBytesNoCopy:(void *)vector
                                       length:_dimension * sizeof(float)
                                 freeWhenDone:NO];
    @try {
        [_spillWrite writeData:row];
    } @catch (NSException *e) {
        return NO;
    }
    return YES;
}

// Stream the spill file in bounded chunks and score each chunk with the same
// batched engine used for the hot set.
- (BOOL)scoreSpilledForQuery:(const float *)query intoScores:(float *)outScores {
    NSFileHandle *reader = [NSFileHandle fileHandleForReadingAtPath:_spillPath];
    if (!reader) return NO;

    const NSUInteger rowBytes = _dimension * sizeof(float);
    const NSUInteger chunkVectors = std::max((NSUInteger)1, kSpillChunkMaxBytes / rowBytes);
    NSUInteger done = 0;
    BOOL ok = YES;

    @try {
        while (ok && done < _spilledCount) {
            NSUInteger want = std::min(chunkVectors, _spilledCount - done);
            NSData *chunk = [reader readDataOfLength:want * rowBytes];
            if (chunk.length != want * rowBytes) { ok = NO; break; }
            ok = [_engine scoresForQuery:query
                                 vectors:(const float *)chunk.bytes
                                   count:want dimension:_dimension
                               outScores:outScores + done];
            done += want;
        }
    } @catch (NSException *e) {
        ok = NO;
    } @finally {
        [reader closeFile];
    }
    return ok;
}

- (void)closeSpillFileAndUnlink {
    if (_spillWrite) {
        [_spillWrite closeFile];
        _spillWrite = nil;
    }
    if (_spillPath) {
        [[NSFileManager defaultManager] removeItemAtPath:_spillPath error:nil];
        _spillPath = nil;
    }
}

@end
