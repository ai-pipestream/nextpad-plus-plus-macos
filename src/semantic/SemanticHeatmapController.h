#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class EditorView;
@class SemanticHeatmapController;

/// Status callbacks for the search bar ("Indexing 214 sentences…",
/// "214 sentences · Metal/MPS", "Document too large", …). Always on main.
@protocol SemanticHeatmapControllerDelegate <NSObject>
- (void)semanticHeatmap:(SemanticHeatmapController *)controller
        statusDidChange:(NSString *)status
                   busy:(BOOL)busy;
@end

/// Orchestrates the semantic sentence heatmap for one attached EditorView:
///   1. splits the document into sentences with NLTokenizer (stable ids →
///      Scintilla byte ranges),
///   2. embeds them via a SemanticEmbeddingProvider (Apple NaturalLanguage),
///   3. keeps them in a SemanticVectorIndex (in-memory hot set + disk spill),
///   4. on each query, scores every sentence with a SemanticSimilarityEngine
///      (Metal/MPS, Accelerate fallback) and paints a red→grey→green heatmap
///      using Scintilla indicator 20 with per-range colors
///      (SC_INDICFLAG_VALUEFORE).
///
/// Document edits invalidate the index and trigger a debounced rebuild;
/// unchanged sentences re-use cached embeddings, so incremental typing does
/// not re-run the model on the whole document.
///
/// All embedding/index/scoring work runs on a private serial queue; Scintilla
/// is only ever touched on the main thread. The feature soft-requires
/// macOS 14 (+isFeatureAvailable) — on older systems nothing is constructed
/// and the rest of the app is unaffected.
@interface SemanticHeatmapController : NSObject

/// YES on macOS 14+. (The embedding model itself is validated lazily; if it
/// fails to load the delegate gets an explanatory status instead.)
+ (BOOL)isFeatureAvailable;

@property (nonatomic, weak, nullable) id<SemanticHeatmapControllerDelegate> delegate;

/// Editor currently driving the heatmap (nil when detached).
@property (nonatomic, readonly, weak, nullable) EditorView *editor;

/// Attach to an editor: builds the sentence index for its current content and
/// starts watching it for edits. Re-attaching to the same editor is a no-op;
/// attaching to a different one clears the old editor's heatmap first.
- (void)attachToEditor:(EditorView *)editor;

/// Clear the heatmap, stop watching, forget the editor.
- (void)detach;

/// Live query update. Empty string clears the heatmap but keeps the index warm.
- (void)updateQuery:(NSString *)query;

/// Remove all heatmap coloring from the attached editor.
- (void)clearHeatmap;

@end

NS_ASSUME_NONNULL_END
