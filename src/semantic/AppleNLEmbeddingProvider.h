#import <Foundation/Foundation.h>
#import "SemanticProtocols.h"

NS_ASSUME_NONNULL_BEGIN

/// SemanticEmbeddingProvider backed by Apple's NaturalLanguage framework.
///
/// Preferred backend: NLContextualEmbedding (macOS 14+), per-token vectors
/// mean-pooled into one sentence vector. Its model assets may require a
/// one-time download; while missing, the asset request is kicked off and
/// NLEmbedding's static sentence embedding is used instead.
///
/// Vectors are L2-normalized. Model loading happens in init and can block —
/// construct off the main thread.
API_AVAILABLE(macos(14.0))
@interface AppleNLEmbeddingProvider : NSObject <SemanticEmbeddingProvider>

/// languageHint is a BCP-47 NLLanguage value (e.g. @"en"); nil defaults to
/// English.
- (instancetype)initWithLanguageHint:(nullable NSString *)languageHint;

/// Backend in use: @"contextual" (NLContextualEmbedding) or @"sentence"
/// (NLEmbedding); nil if none loaded.
@property (nonatomic, readonly, nullable) NSString *backendName;

@end

NS_ASSUME_NONNULL_END
