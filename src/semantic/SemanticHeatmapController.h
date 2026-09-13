#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class EditorView;
@class SemanticHeatmapController;

/// Status callbacks for the search bar ("Indexing…", "214 sentences ·
/// Metal/MPS", errors). Always delivered on the main thread.
@protocol SemanticHeatmapControllerDelegate <NSObject>
- (void)semanticHeatmap:(SemanticHeatmapController *)controller
        statusDidChange:(NSString *)status
                   busy:(BOOL)busy;
@end

/// Drives the semantic sentence heatmap for one attached EditorView:
/// splits the document into sentences (NLTokenizer, stable ids → Scintilla
/// byte ranges), embeds them via SemanticEmbeddingProvider, keeps them in a
/// SemanticVectorIndex, and on each query scores every sentence with a
/// SemanticSimilarityEngine and paints indicator 20 with per-range colors.
///
/// Edits trigger a debounced rebuild; unchanged sentences reuse cached
/// embeddings. All pipeline work runs on a private serial queue; Scintilla is
/// only touched on the main thread. The feature requires macOS 14
/// (+isFeatureAvailable); older systems are unaffected.
@interface SemanticHeatmapController : NSObject

/// YES on macOS 14+. Model/GPU availability is validated lazily; failures are
/// reported through the delegate status.
+ (BOOL)isFeatureAvailable;

@property (nonatomic, weak, nullable) id<SemanticHeatmapControllerDelegate> delegate;

/// Editor currently driving the heatmap (nil when detached).
@property (nonatomic, readonly, weak, nullable) EditorView *editor;

/// Color sensitivity: -1 stricter, 0 standard, 1 broader. Scores are unchanged.
@property (nonatomic) NSInteger sensitivity;

/// Build the sentence index for the editor's content and watch it for edits.
/// Re-attaching to the same editor is a no-op; attaching to a different one
/// clears the old editor's heatmap first.
- (void)attachToEditor:(EditorView *)editor;

/// Clear the heatmap, stop watching, forget the editor.
- (void)detach;

/// Live query update. Empty string clears the heatmap but keeps the index warm.
- (void)updateQuery:(NSString *)query;

/// Remove all heatmap coloring from the attached editor.
- (void)clearHeatmap;

@end

NS_ASSUME_NONNULL_END
