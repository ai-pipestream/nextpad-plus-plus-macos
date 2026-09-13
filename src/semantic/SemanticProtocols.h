#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One scored result from a vector index query. sentenceID is the stable id
/// assigned by the caller; score is cosine similarity in [-1, 1] (vectors are
/// L2-normalized on insert, so dot product == cosine).
typedef struct {
    int64_t sentenceID;
    float   score;
} SemanticHit;

/// Embeds natural-language strings into fixed-dimension float vectors.
/// Vectors written by -embedString:into: must be L2-normalized. Model loading
/// may block — construct and use off the main thread.
@protocol SemanticEmbeddingProvider <NSObject>

/// Vector dimension. 0 means the provider failed to initialize.
@property (nonatomic, readonly) NSUInteger dimension;

/// YES once a usable model is loaded.
@property (nonatomic, readonly, getter=isAvailable) BOOL available;

/// Embed one string into outVector (must hold `dimension` floats).
/// Returns NO if the string could not be embedded.
- (BOOL)embedString:(NSString *)string into:(float *)outVector;

@end

/// Computes similarity scores between one query vector and a batch of vectors.
/// `vectors` is row-major, count × dimension floats, contiguous. All vectors
/// (including the query) are assumed L2-normalized, so only batched dot
/// products are needed.
@protocol SemanticSimilarityEngine <NSObject>

/// Backend name for status display (e.g. "Metal/MPS").
@property (nonatomic, readonly) NSString *engineName;

/// Write `count` cosine scores into outScores. Returns NO on failure.
- (BOOL)scoresForQuery:(const float *)query
               vectors:(const float *)vectors
                 count:(NSUInteger)count
             dimension:(NSUInteger)dimension
             outScores:(float *)outScores;

@end

/// Stores sentence vectors keyed by stable ids and scores queries against
/// them. Expressed as (query, k) → scored ids so an ANN backend can replace
/// the brute-force implementation without touching callers.
@protocol SemanticVectorIndex <NSObject>

@property (nonatomic, readonly) NSUInteger dimension;
@property (nonatomic, readonly) NSUInteger count;

/// Clear everything and fix the vector dimension for subsequent adds.
- (void)resetWithDimension:(NSUInteger)dimension;

/// Append one L2-normalized vector under a caller-chosen stable id.
- (BOOL)addVector:(const float *)vector sentenceID:(int64_t)sentenceID;

/// Score every stored vector against the query (heatmap path). Writes up to
/// `capacity` hits, returns how many. Order is unspecified.
- (NSUInteger)scoreAllForQuery:(const float *)query
                          hits:(SemanticHit *)hits
                      capacity:(NSUInteger)capacity;

/// Top-k search. Writes at most k hits sorted by descending score, returns
/// how many were written.
- (NSUInteger)search:(const float *)query
                   k:(NSUInteger)k
                hits:(SemanticHit *)hits;

@end

NS_ASSUME_NONNULL_END
