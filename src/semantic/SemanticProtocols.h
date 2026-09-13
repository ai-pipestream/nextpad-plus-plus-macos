#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One scored result from a vector index query.
/// sentenceID is the stable id assigned by the caller (SemanticHeatmapController
/// maps it back to a Scintilla byte range); score is cosine similarity in [-1, 1]
/// (vectors are L2-normalized on the way in, so dot product == cosine).
typedef struct {
    int64_t sentenceID;
    float   score;
} SemanticHit;

/// Embeds natural-language strings into fixed-dimension float vectors.
///
/// Contract: vectors written by -embedString:into: are L2-normalized so that
/// downstream engines can treat dot product as cosine similarity.
/// Implementations may be slow to initialize (model load) — construct and use
/// them off the main thread. First implementation: AppleNLEmbeddingProvider
/// (NLContextualEmbedding, mean-pooled, with NLEmbedding sentence fallback).
/// A future on-device transformer or remote provider only needs this protocol.
@protocol SemanticEmbeddingProvider <NSObject>

/// Vector dimension. 0 means the provider failed to initialize.
@property (nonatomic, readonly) NSUInteger dimension;

/// YES once a usable model is loaded.
@property (nonatomic, readonly, getter=isAvailable) BOOL available;

/// Embed one string into outVector (must hold `dimension` floats).
/// Returns NO if the string could not be embedded (caller should skip it).
- (BOOL)embedString:(NSString *)string into:(float *)outVector;

@end

/// Computes similarity scores between one query vector and a batch of vectors.
///
/// Inputs are row-major: `vectors` is count × dimension floats, contiguous.
/// All vectors (including the query) are assumed L2-normalized, so the engine
/// only needs batched dot products. Sole shipped implementation:
/// MetalSimilarityEngine (MPSMatrixVectorMultiplication on the GPU). There is
/// deliberately NO CPU fallback — when Metal/MPS is unavailable the feature
/// fails loud in the UI. Alternative backends still plug in via this protocol.
@protocol SemanticSimilarityEngine <NSObject>

/// Human-readable backend name for status/debugging (e.g. "Metal/MPS").
@property (nonatomic, readonly) NSString *engineName;

/// Write `count` cosine scores into outScores. Returns NO on failure
/// (caller should fall back to another engine).
- (BOOL)scoresForQuery:(const float *)query
               vectors:(const float *)vectors
                 count:(NSUInteger)count
             dimension:(NSUInteger)dimension
             outScores:(float *)outScores;

@end

/// Stores sentence vectors keyed by stable sentence ids and scores queries
/// against them.
///
/// The v1 implementation (SpillableVectorIndex) is an exact brute-force scan:
/// a hot contiguous RAM buffer plus a disk spill buffer for overflow. The
/// protocol is deliberately index-agnostic — search: is expressed as
/// (query, k) → scored ids — so an ANN backend (e.g. turbovec) can be swapped
/// in later without touching the controller.
@protocol SemanticVectorIndex <NSObject>

@property (nonatomic, readonly) NSUInteger dimension;
@property (nonatomic, readonly) NSUInteger count;

/// Clear everything and fix the vector dimension for subsequent adds.
- (void)resetWithDimension:(NSUInteger)dimension;

/// Append one L2-normalized vector under a caller-chosen stable id.
- (BOOL)addVector:(const float *)vector sentenceID:(int64_t)sentenceID;

/// Score EVERY stored vector against the query (heatmap path).
/// Writes up to `capacity` hits and returns how many were written.
/// Order of hits is unspecified.
- (NSUInteger)scoreAllForQuery:(const float *)query
                          hits:(SemanticHit *)hits
                      capacity:(NSUInteger)capacity;

/// Top-k search (classic vector-index API; what an ANN backend would optimize).
/// Writes at most k hits sorted by descending score, returns how many.
- (NSUInteger)search:(const float *)query
                   k:(NSUInteger)k
                hits:(SemanticHit *)hits;

@end

NS_ASSUME_NONNULL_END
