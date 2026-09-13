#import "SemanticHeatmapController.h"
#import "EditorView.h"
#import "SemanticProtocols.h"
#import "AppleNLEmbeddingProvider.h"
#import "MetalSimilarityEngine.h"
#import "SpillableVectorIndex.h"
#import <NaturalLanguage/NaturalLanguage.h>
#include "Scintilla.h"
#include <algorithm>
#include <memory>
#include <vector>

// ── Indicator choice ─────────────────────────────────────────────────────────
// Slot 20 is unused in this app: 0-7 belong to lexers, 8 is smart highlight,
// 9-13 are the five mark styles, 17 spell check, 18 git diff, 19 clickable
// links, 28 incremental search. One slot suffices for the whole heatmap
// because SC_INDICFLAG_VALUEFORE makes each filled range take its fill color
// from the per-range indicator VALUE — i.e. true continuous coloring.
static const int kSemanticHeatmapIndicator = 20;

// ── Size guards ──────────────────────────────────────────────────────────────
// Contextual embedding costs ~1ms+ per sentence; cap work so the editor never
// wedges on a giant file. Beyond these limits the feature reports
// "Document too large" instead of degrading the app.
static const long       kMaxDocBytes  = 2 * 1024 * 1024;
static const NSUInteger kMaxSentences = 4096;

// Debounce for index rebuild after document edits.
static const int64_t kRebuildDebounceNs = (int64_t)(0.6 * NSEC_PER_SEC);

// Sentence span: stable id → Scintilla byte range for the CURRENT build.
// Ids are globally increasing; spans of a build are contiguous starting at
// firstSentenceID, so hit.sentenceID - firstSentenceID indexes _spans.
struct NppSentenceSpan {
    long byteStart;
    long byteLength;
};

// Red → grey → green ramp (as {r,g,b} 0-255). t = 0 least similar, 1 most.
static sptr_t nppHeatColorBGR(double t) {
    static const int lo[3]  = { 0xD6, 0x45, 0x41 };  // red    #D64541
    static const int mid[3] = { 0x8E, 0x8E, 0x8E };  // grey   #8E8E8E
    static const int hi[3]  = { 0x2E, 0xCC, 0x71 };  // green  #2ECC71
    t = std::min(1.0, std::max(0.0, t));
    const int *a = (t < 0.5) ? lo  : mid;
    const int *b = (t < 0.5) ? mid : hi;
    double f = (t < 0.5) ? t * 2.0 : (t - 0.5) * 2.0;
    int r = (int)(a[0] + (b[0] - a[0]) * f);
    int g = (int)(a[1] + (b[1] - a[1]) * f);
    int bl = (int)(a[2] + (b[2] - a[2]) * f);
    return (sptr_t)((bl << 16) | (g << 8) | r);   // Scintilla wants BGR
}

@implementation SemanticHeatmapController {
    EditorView *__weak _editor;

    // Pipeline components (protocol-typed — swap implementations freely).
    // Confined to _workQueue after creation.
    id<SemanticEmbeddingProvider> _provider;
    id<SemanticVectorIndex>       _index;
    id<SemanticSimilarityEngine>  _engine;

    dispatch_queue_t _workQueue;

    // Embedding cache: sentence text → vector bytes. Survives rebuilds so an
    // edit only re-embeds sentences whose text actually changed.
    NSCache<NSString *, NSData *> *_embedCache;

    // Main-thread state.
    std::vector<NppSentenceSpan> _spans;    // spans of the current build
    int64_t   _firstSentenceID;
    int64_t   _nextSentenceID;
    BOOL      _indexReady;
    NSString *_query;

    // Generations: bumped on main whenever inputs change; background results
    // carrying a stale generation are dropped on arrival.
    uint64_t _buildGeneration;
    uint64_t _queryGeneration;
    uint64_t _pendingRebuildToken;  // debounce token for edit-triggered rebuilds
}

+ (BOOL)isFeatureAvailable {
    if (@available(macOS 14.0, *)) return YES;
    return NO;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _workQueue = dispatch_queue_create("org.nextpadplusplus.semantic-heatmap",
                                       DISPATCH_QUEUE_SERIAL);
    _embedCache = [[NSCache alloc] init];
    _embedCache.countLimit = 3 * kMaxSentences;  // a few documents' worth
    _query = @"";
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (EditorView *)editor { return _editor; }

#pragma mark - Attach / detach

- (void)attachToEditor:(EditorView *)editor {
    if (editor == _editor) return;
    [self clearHeatmap];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:EditorViewTextDidChangeNotification object:nil];

    _editor = editor;
    _indexReady = NO;
    if (!editor) return;

    [self configureIndicatorOn:editor];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(_editorTextDidChange:)
               name:EditorViewTextDidChangeNotification object:editor];
    [self rebuildIndex];
}

- (void)detach {
    [self clearHeatmap];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:EditorViewTextDidChangeNotification object:nil];
    _editor = nil;
    _indexReady = NO;
    _buildGeneration++;
    _queryGeneration++;
}

- (void)configureIndicatorOn:(EditorView *)editor {
    ScintillaView *sci = editor.scintillaView;
    [sci message:SCI_INDICSETSTYLE wParam:kSemanticHeatmapIndicator lParam:INDIC_FULLBOX];
    [sci message:SCI_INDICSETFLAGS wParam:kSemanticHeatmapIndicator lParam:SC_INDICFLAG_VALUEFORE];
    [sci message:SCI_INDICSETALPHA wParam:kSemanticHeatmapIndicator lParam:45];
    [sci message:SCI_INDICSETOUTLINEALPHA wParam:kSemanticHeatmapIndicator lParam:0];
    [sci message:SCI_INDICSETUNDER wParam:kSemanticHeatmapIndicator lParam:1]; // under text
}

#pragma mark - Document edits → debounced rebuild

- (void)_editorTextDidChange:(NSNotification *)note {
    if (note.object != _editor) return;
    // Invalidate immediately (in-flight results become stale), rebuild lazily.
    _indexReady = NO;
    _buildGeneration++;
    uint64_t token = ++_pendingRebuildToken;
    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kRebuildDebounceNs),
                   dispatch_get_main_queue(), ^{
        __typeof(self) self_ = weakSelf;
        if (!self_ || token != self_->_pendingRebuildToken) return;  // superseded
        [self_ rebuildIndex];
    });
}

#pragma mark - Index rebuild

- (void)rebuildIndex {
    EditorView *editor = _editor;
    if (!editor) return;
    ScintillaView *sci = editor.scintillaView;

    sptr_t docLen = [sci message:SCI_GETLENGTH];
    if (editor.largeFileMode || docLen > kMaxDocBytes) {
        [self reportStatus:@"Document too large for semantic search" busy:NO];
        return;
    }

    // Snapshot the document bytes NOW, on the main thread — the character
    // pointer is only valid until the next edit.
    const char *chars = (const char *)[sci message:SCI_GETCHARACTERPOINTER];
    NSData *docBytes = chars ? [NSData dataWithBytes:chars length:(NSUInteger)docLen]
                             : [NSData data];

    uint64_t gen = ++_buildGeneration;
    int64_t firstID = _nextSentenceID;
    [self reportStatus:@"Indexing…" busy:YES];

    __weak __typeof(self) weakSelf = self;
    dispatch_async(_workQueue, ^{
        __typeof(self) self_ = weakSelf;
        if (!self_) return;

        NSString *text = [[NSString alloc] initWithData:docBytes
                                               encoding:NSUTF8StringEncoding];
        NSMutableArray<NSString *> *sentences = [NSMutableArray array];
        auto spans = std::make_shared<std::vector<NppSentenceSpan>>();

        if (text.length) {
            // NLTokenizer ranges are UTF-16; walk forward converting each gap
            // and sentence to UTF-8 byte lengths so spans line up with
            // Scintilla byte positions.
            NLTokenizer *tok = [[NLTokenizer alloc] initWithUnit:NLTokenUnitSentence];
            tok.string = text;
            __block NSUInteger lastU16 = 0;
            __block long lastByte = 0;
            [tok enumerateTokensInRange:NSMakeRange(0, text.length)
                             usingBlock:^(NSRange r, NLTokenizerAttributes attrs, BOOL *stop) {
                NSString *gap = [text substringWithRange:
                                    NSMakeRange(lastU16, r.location - lastU16)];
                NSString *sentence = [text substringWithRange:r];
                long byteStart = lastByte +
                    (long)[gap lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                long byteLen =
                    (long)[sentence lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                lastU16  = NSMaxRange(r);
                lastByte = byteStart + byteLen;

                NSString *trimmed = [sentence stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (trimmed.length == 0) return;

                [sentences addObject:sentence];
                spans->push_back(NppSentenceSpan{ byteStart, byteLen });
                if (sentences.count >= kMaxSentences) *stop = YES;
            }];
        }

        NSString *pipelineError = [self_ ensurePipelineForSample:text];
        if (pipelineError) {
            [self_ reportStatus:pipelineError busy:NO];
            return;
        }

        // Embed + index. Cached vectors skip the model entirely.
        NSUInteger dim = self_->_provider.dimension;
        [self_->_index resetWithDimension:dim];
        std::vector<float> scratch(dim);
        int64_t sid = firstID;
        NSUInteger embedded = 0;
        for (NSString *s in sentences) {
            NSData *cached = [self_->_embedCache objectForKey:s];
            if (cached.length == dim * sizeof(float)) {
                memcpy(scratch.data(), cached.bytes, cached.length);
            } else if ([self_->_provider embedString:s into:scratch.data()]) {
                [self_->_embedCache setObject:[NSData dataWithBytes:scratch.data()
                                                             length:dim * sizeof(float)]
                                       forKey:s];
            } else {
                // Unembeddable sentence — keep ids aligned with spans by
                // storing a zero vector (scores ~0, painted as mid/greyish).
                std::fill(scratch.begin(), scratch.end(), 0.0f);
            }
            [self_->_index addVector:scratch.data() sentenceID:sid++];
            embedded++;
        }

        NSString *status = [NSString stringWithFormat:@"%lu sentences · %@",
                            (unsigned long)embedded, self_->_engine.engineName];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gen != self_->_buildGeneration) return;   // superseded by an edit
            self_->_spans = *spans;
            self_->_firstSentenceID = firstID;
            self_->_nextSentenceID  = firstID + (int64_t)spans->size();
            self_->_indexReady = YES;
            [self_ reportStatus:status busy:NO];
            if (self_->_query.length) [self_ runQuery];
        });
    });
}

/// Create provider / engine / index on first use (work queue). Returns nil on
/// success or a user-facing error string. FAIL-LOUD policy: if Metal/MPS is
/// missing or unsupported the whole feature is unavailable — there is no
/// silent CPU fallback, the error is surfaced in the search bar instead.
- (nullable NSString *)ensurePipelineForSample:(nullable NSString *)sampleText {
    if (_provider && _provider.isAvailable && _engine) return nil;
    if (@available(macOS 14.0, *)) {
        if (!_engine) {
            _engine = [MetalSimilarityEngine engineIfAvailable];
            if (!_engine)
                return @"Metal GPU unavailable — semantic search disabled";
        }
        if (!_provider || !_provider.isAvailable) {
            NSString *lang = nil;
            if (sampleText.length) {
                NSString *sample = sampleText.length > 2048
                    ? [sampleText substringToIndex:2048] : sampleText;
                lang = [NLLanguageRecognizer dominantLanguageForString:sample];
            }
            _provider = [[AppleNLEmbeddingProvider alloc] initWithLanguageHint:lang];
            if (!_provider.isAvailable) {
                _provider = nil;
                return @"Embedding model unavailable on this Mac";
            }
        }
        if (!_index) _index = [[SpillableVectorIndex alloc] initWithSimilarityEngine:_engine];
        return nil;
    }
    return @"Requires macOS 14 or later";
}

#pragma mark - Query → heatmap

- (void)updateQuery:(NSString *)query {
    _query = [query copy] ?: @"";
    if (_query.length == 0) {
        _queryGeneration++;
        [self clearHeatmap];
        return;
    }
    if (!_indexReady) return;   // rebuild completion re-runs the query
    [self runQuery];
}

- (void)runQuery {
    NSString *query = _query;
    uint64_t qGen = ++_queryGeneration;
    uint64_t bGen = _buildGeneration;
    if (!_editor || !query.length) return;

    __weak __typeof(self) weakSelf = self;
    dispatch_async(_workQueue, ^{
        __typeof(self) self_ = weakSelf;
        if (!self_ || !self_->_provider) return;

        NSUInteger dim = self_->_provider.dimension;
        std::vector<float> qVec(dim);
        if (![self_->_provider embedString:query into:qVec.data()]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (qGen != self_->_queryGeneration) return;
                [self_ reportStatus:@"Query could not be embedded" busy:NO];
            });
            return;
        }

        NSUInteger n = self_->_index.count;
        auto hits = std::make_shared<std::vector<SemanticHit>>(n);
        NSUInteger got = n ? [self_->_index scoreAllForQuery:qVec.data()
                                                        hits:hits->data()
                                                    capacity:n] : 0;
        hits->resize(got);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (qGen != self_->_queryGeneration ||
                bGen != self_->_buildGeneration) return;   // stale
            [self_ paintHits:*hits];
        });
    });
}

// Main thread. Maps scores → colors and fills indicator 20 per sentence.
- (void)paintHits:(const std::vector<SemanticHit> &)hits {
    EditorView *editor = _editor;
    if (!editor) return;
    ScintillaView *sci = editor.scintillaView;
    sptr_t docLen = [sci message:SCI_GETLENGTH];

    [sci message:SCI_SETINDICATORCURRENT wParam:kSemanticHeatmapIndicator];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:docLen];
    if (hits.empty()) return;

    // Normalize this query's score distribution to [0,1] so the ramp always
    // uses its full red→grey→green width (raw cosine values cluster).
    float minS = hits[0].score, maxS = hits[0].score;
    for (const SemanticHit &h : hits) {
        minS = std::min(minS, h.score);
        maxS = std::max(maxS, h.score);
    }
    float range = maxS - minS;

    for (const SemanticHit &h : hits) {
        size_t idx = (size_t)(h.sentenceID - _firstSentenceID);
        if (idx >= _spans.size()) continue;
        const NppSentenceSpan &span = _spans[idx];
        if (span.byteStart >= docLen) continue;
        long len = std::min((long)span.byteLength, (long)(docLen - span.byteStart));

        double t = (range > 1e-6) ? (double)(h.score - minS) / range : 0.5;
        [sci message:SCI_SETINDICATORVALUE
              wParam:(uptr_t)(nppHeatColorBGR(t) | SC_INDICVALUEBIT)];
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)span.byteStart lParam:len];
    }
}

- (void)clearHeatmap {
    EditorView *editor = _editor;
    if (!editor) return;
    ScintillaView *sci = editor.scintillaView;
    [sci message:SCI_SETINDICATORCURRENT wParam:kSemanticHeatmapIndicator];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0
          lParam:[sci message:SCI_GETLENGTH]];
}

- (void)reportStatus:(NSString *)status busy:(BOOL)busy {
    id<SemanticHeatmapControllerDelegate> delegate = self.delegate;
    if (!delegate) return;
    if (NSThread.isMainThread) {
        [delegate semanticHeatmap:self statusDidChange:status busy:busy];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate semanticHeatmap:self statusDidChange:status busy:busy];
        });
    }
}

@end
