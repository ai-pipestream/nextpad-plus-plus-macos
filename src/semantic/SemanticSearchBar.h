#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Delegate for the semantic heatmap search bar.
@protocol SemanticSearchBarDelegate <NSObject>
/// Fired (debounced) as the user types. Empty string means "clear heatmap".
- (void)semanticSearchBar:(id)bar queryDidChange:(NSString *)query;
- (void)semanticSearchBarDidClose:(id)bar;
@end

/// Narrow live-search bar shown below the editor — the semantic sibling of
/// IncrementalSearchBar. The user types a natural-language query and every
/// sentence in the document is tinted red→grey→green by similarity. Typing is
/// debounced since each query update runs the embedding model.
@interface SemanticSearchBar : NSView <NSTextFieldDelegate, NSControlTextEditingDelegate>

@property (nonatomic, weak, nullable) id<SemanticSearchBarDelegate> delegate;

/// Preferred height when visible.
@property (nonatomic, readonly) CGFloat preferredHeight;

/// Make the query field first responder.
- (void)activate;

/// Dismiss the bar and clear the heatmap.
- (void)close;

/// Show pipeline status ("Indexing…", "214 sentences · Metal/MPS", errors).
- (void)setStatus:(NSString *)text busy:(BOOL)busy;

@end

NS_ASSUME_NONNULL_END
