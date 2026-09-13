#import "AppleNLEmbeddingProvider.h"
#import <NaturalLanguage/NaturalLanguage.h>
#include <cmath>
#include <vector>

// L2-normalize in place. Returns NO for a zero vector (nothing to normalize —
// caller should treat the embed as failed rather than divide by zero).
static BOOL nppL2Normalize(float *v, NSUInteger dim) {
    double sumSq = 0;
    for (NSUInteger i = 0; i < dim; i++) sumSq += (double)v[i] * (double)v[i];
    if (sumSq <= 0) return NO;
    float inv = (float)(1.0 / sqrt(sumSq));
    for (NSUInteger i = 0; i < dim; i++) v[i] *= inv;
    return YES;
}

@implementation AppleNLEmbeddingProvider {
    NLContextualEmbedding *_contextual;   // preferred (macOS 14+)
    NLEmbedding           *_sentence;     // fallback (static sentence embedding)
    NLLanguage             _language;
    NSUInteger             _dimension;
}

@synthesize backendName = _backendName;

- (instancetype)initWithLanguageHint:(nullable NSString *)languageHint {
    self = [super init];
    if (!self) return nil;

    _language = languageHint.length ? languageHint : NLLanguageEnglish;

    // ── Preferred: contextual token embedding, mean-pooled per sentence ──────
    NLContextualEmbedding *ctx = [NLContextualEmbedding contextualEmbeddingWithLanguage:_language];
    if (!ctx && ![_language isEqualToString:NLLanguageEnglish])
        ctx = [NLContextualEmbedding contextualEmbeddingWithLanguage:NLLanguageEnglish];

    if (ctx) {
        if (ctx.hasAvailableAssets) {
            NSError *err = nil;
            if ([ctx loadWithError:&err]) {
                _contextual = ctx;
                _dimension  = ctx.dimension;
                _backendName = @"contextual";
            }
        } else {
            // Assets not on disk yet — request the on-demand download so the
            // contextual backend is available on a future launch, and fall
            // through to the static sentence embedding for this session.
            [ctx requestEmbeddingAssetsWithCompletionHandler:
                ^(NLContextualEmbeddingAssetsResult result, NSError *_Nullable error) { /* fire-and-forget */ }];
        }
    }

    // ── Fallback: static sentence embedding (no asset download needed) ───────
    if (!_contextual) {
        NLEmbedding *sent = [NLEmbedding sentenceEmbeddingForLanguage:_language];
        if (!sent && ![_language isEqualToString:NLLanguageEnglish])
            sent = [NLEmbedding sentenceEmbeddingForLanguage:NLLanguageEnglish];
        if (sent) {
            _sentence   = sent;
            _dimension  = sent.dimension;
            _backendName = @"sentence";
        }
    }

    return self;
}

- (NSUInteger)dimension { return _dimension; }
- (BOOL)isAvailable     { return _dimension > 0; }

- (BOOL)embedString:(NSString *)string into:(float *)outVector {
    if (_dimension == 0 || string.length == 0) return NO;

    if (_contextual) {
        NSError *err = nil;
        NLContextualEmbeddingResult *result =
            [_contextual embeddingResultForString:string language:_language error:&err];
        if (!result) return NO;

        // Mean-pool the per-token vectors into one sentence vector.
        std::vector<double> acc(_dimension, 0.0);
        __block NSUInteger tokenCount = 0;
        NSUInteger dim = _dimension;
        double *accPtr = acc.data();
        [result enumerateTokenVectorsInRange:NSMakeRange(0, string.length)
                                  usingBlock:^(NSArray<NSNumber *> *tokenVector,
                                               NSRange tokenRange, BOOL *stop) {
            if (tokenVector.count != dim) return;
            for (NSUInteger i = 0; i < dim; i++)
                accPtr[i] += tokenVector[i].doubleValue;
            tokenCount++;
        }];
        if (tokenCount == 0) return NO;
        for (NSUInteger i = 0; i < _dimension; i++)
            outVector[i] = (float)(acc[i] / (double)tokenCount);
        return nppL2Normalize(outVector, _dimension);
    }

    if (_sentence) {
        if (![_sentence getVector:outVector forString:string]) return NO;
        return nppL2Normalize(outVector, _dimension);
    }

    return NO;
}

@end
