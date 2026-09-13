#import <Foundation/Foundation.h>
#import "SemanticProtocols.h"

NS_ASSUME_NONNULL_BEGIN

/// SemanticEmbeddingProvider backed by Apple's NaturalLanguage framework.
///
/// Preferred backend (macOS 14+): NLContextualEmbedding — per-token contextual
/// vectors mean-pooled into one sentence vector. Its model assets may need a
/// one-time on-demand download; while they are missing we kick off the asset
/// request and fall back to NLEmbedding's static sentence embedding
/// (available since macOS 11) so the feature still works immediately.
///
/// All vectors returned are L2-normalized. Model loading happens in init and
/// can block for a moment — construct this object off the main thread.
API_AVAILABLE(macos(14.0))
@interface AppleNLEmbeddingProvider : NSObject <SemanticEmbeddingProvider>

/// Loads models for `languageHint` (a BCP-47 NLLanguage value such as @"en").
/// Pass nil to default to English; the heatmap controller passes the dominant
/// language detected in the document.
- (instancetype)initWithLanguageHint:(nullable NSString *)languageHint;

/// Backend actually in use, for status display:
/// @"contextual" (NLContextualEmbedding) or @"sentence" (NLEmbedding), nil if none.
@property (nonatomic, readonly, nullable) NSString *backendName;

@end

NS_ASSUME_NONNULL_END
