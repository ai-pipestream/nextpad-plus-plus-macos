#import "SemanticSearchBar.h"
#import "NppLocalizer.h"
#import "NppThemeManager.h"
#include "SemanticHeatmapColors.h"

static NSString * const kSensitivityPreference = @"SemanticHeatmapSensitivity";
static const CGFloat        kBarHeight        = 62.0;
static const NSTimeInterval kQueryDebounceSec = 0.30;

@implementation SemanticSearchBar {
    NSTextField *_titleLabel;
    NSTextField *_queryField;
    NSTextField *_legendLabel;
    NSTextField *_statusLabel;
    NSProgressIndicator *_spinner;
    NSButton    *_closeBtn;
    NSTimer     *_debounceTimer;
    NSPopUpButton *_sensitivityPopup;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.wantsLayer = YES;
    self.layer.backgroundColor = [NppThemeManager shared].statusBarBackground.CGColor;
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(_darkModeChanged:)
               name:NPPDarkModeChangedNotification object:nil];

    // Separator at the top
    NSBox *sep = [[NSBox alloc] init];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:sep];

    _titleLabel = [NSTextField labelWithString:@"Semantic:"];
    _titleLabel.font = [NSFont systemFontOfSize:12];
    _titleLabel.textColor = [NSColor secondaryLabelColor];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _queryField = [NSTextField textFieldWithString:@""];
    _queryField.translatesAutoresizingMaskIntoConstraints = NO;
    _queryField.delegate = self;
    [[_queryField cell] setScrollable:YES];

    // Legend: colored squares from least to most similar.
    _legendLabel = [NSTextField labelWithAttributedString:[self legendString]];
    _legendLabel.font = [NSFont systemFontOfSize:11];
    _legendLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _legendLabel.toolTip = @"Least → most similar";

    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_statusLabel setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];

    _sensitivityPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _sensitivityPopup.translatesAutoresizingMaskIntoConstraints = NO;
    _sensitivityPopup.controlSize = NSControlSizeSmall;
    _sensitivityPopup.target = self;
    _sensitivityPopup.action = @selector(sensitivityChanged:);
    [_sensitivityPopup addItemsWithTitles:@[@"Strict", @"Standard", @"Broad"]];
    NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:kSensitivityPreference];
    [_sensitivityPopup selectItemAtIndex:std::clamp(saved, (NSInteger)-1, (NSInteger)1) + 1];

    _closeBtn = [NSButton buttonWithTitle:@"✕" target:self action:@selector(closeBar:)];
    _closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _closeBtn.bezelStyle = NSBezelStyleInline;
    _closeBtn.font = [NSFont systemFontOfSize:12];

    for (NSView *v in @[_titleLabel, _queryField, _legendLabel,
                        _spinner, _statusLabel, _closeBtn, _sensitivityPopup])
        [self addSubview:v];

    NSDictionary *views = @{
        @"sep":    sep,
        @"lbl":    _titleLabel,
        @"field":  _queryField,
        @"legend": _legendLabel,
        @"spin":   _spinner,
        @"status": _statusLabel,
        @"close":  _closeBtn,
        @"sensitivity": _sensitivityPopup,
    };
    NSDictionary *metrics = @{@"pad": @8, @"sp": @4};

    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint
        constraintsWithVisualFormat:@"H:|-(0)-[sep]-(0)-|" options:0 metrics:nil views:views]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint
        constraintsWithVisualFormat:@"H:|-(pad)-[lbl]-(sp)-[field(>=120)]-(8)-[close(24)]-(pad)-|"
                           options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint
        constraintsWithVisualFormat:@"H:|-(pad)-[sensitivity]-(8)-[legend]-(8)-[spin(16)]-(sp)-[status(>=0)]-(pad)-|"
                           options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
    [NSLayoutConstraint activateConstraints:@[
        [sep.topAnchor constraintEqualToAnchor:self.topAnchor],
        [sep.heightAnchor constraintEqualToConstant:1],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:self.topAnchor constant:17],
        [_sensitivityPopup.centerYAnchor constraintEqualToAnchor:self.topAnchor constant:45],
    ]];

    [self retranslateUI];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_localizationChanged:)
                                                 name:NPPLocalizationChanged
                                               object:nil];
    return self;
}

- (void)dealloc {
    [_debounceTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSAttributedString *)legendString {
    static const double scores[] = {0.35, 0.60, 0.75, 0.84, 0.90, 0.93};
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    for (int i = 0; i < 6; i++) {
        uint32_t bgr = SemanticHeatmap::colorBGR(scores[i]);
        NSColor *c = [NSColor colorWithRed:(bgr & 255) / 255.0
                                   green:((bgr >> 8) & 255) / 255.0
                                    blue:((bgr >> 16) & 255) / 255.0 alpha:1];
        [s appendAttributedString:
            [[NSAttributedString alloc] initWithString:@"■"
                                            attributes:@{ NSForegroundColorAttributeName: c,
                                                          NSFontAttributeName: [NSFont systemFontOfSize:11] }]];
    }
    return s;
}

- (void)_localizationChanged:(NSNotification *)note { [self retranslateUI]; }

- (void)retranslateUI {
    NppLocalizer *loc = [NppLocalizer shared];
    _titleLabel.stringValue = [loc translate:@"Semantic:"];
    _queryField.placeholderString = [loc translate:@"Describe what you're looking for…"];
    _closeBtn.toolTip = [loc translate:@"Close"];
    [_closeBtn setAccessibilityLabel:[loc translate:@"Close semantic search"]];
    [_queryField setAccessibilityLabel:[loc translate:@"Semantic search query"]];
    NSArray<NSString *> *titles = @[@"Strict", @"Standard", @"Broad"];
    for (NSInteger i = 0; i < 3; ++i)
        [_sensitivityPopup itemAtIndex:i].title = [loc translate:titles[i]];
    [_sensitivityPopup setAccessibilityLabel:[loc translate:@"Heatmap sensitivity"]];
    _sensitivityPopup.toolTip = [loc translate:@"Heatmap sensitivity: Broad colors weaker matches green; Strict requires stronger matches. Scores are unchanged."];
    _legendLabel.toolTip = [loc translate:@"Red: less similar. Grey: intermediate. Green: more similar. Colors depend on sensitivity; they are not confidence percentages."];
    [_legendLabel setAccessibilityLabel:_legendLabel.toolTip];
}

- (CGFloat)preferredHeight { return kBarHeight; }
- (NSInteger)sensitivity { return _sensitivityPopup.indexOfSelectedItem - 1; }
- (NSString *)query { return _queryField.stringValue; }

- (void)sensitivityChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setInteger:self.sensitivity forKey:kSensitivityPreference];
    [_delegate semanticSearchBar:self sensitivityDidChange:self.sensitivity];
}

- (void)activate {
    [self.window makeFirstResponder:_queryField];
}

- (void)close {
    [_debounceTimer invalidate];
    _debounceTimer = nil;
    [_delegate semanticSearchBarDidClose:self];
}

- (void)closeBar:(id)sender { [self close]; }

- (void)setStatus:(NSString *)text busy:(BOOL)busy {
    _statusLabel.stringValue = text ?: @"";
    _statusLabel.toolTip = _statusLabel.stringValue;
    if (busy) [_spinner startAnimation:nil];
    else      [_spinner stopAnimation:nil];
}

#pragma mark - Debounced live query

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object != _queryField) return;
    [_debounceTimer invalidate];
    NSString *query = _queryField.stringValue;
    if (query.length == 0) {
        // Clearing should feel instant — no debounce.
        [_delegate semanticSearchBar:self queryDidChange:@""];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    _debounceTimer = [NSTimer scheduledTimerWithTimeInterval:kQueryDebounceSec
                                                     repeats:NO
                                                       block:^(NSTimer *t) {
        __typeof(self) self_ = weakSelf;
        if (!self_) return;
        [self_->_delegate semanticSearchBar:self_
                             queryDidChange:self_->_queryField.stringValue];
    }];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)tv doCommandBySelector:(SEL)cmd {
    if (control == _queryField) {
        if (cmd == @selector(insertNewline:)) {
            // Enter = run immediately, skipping the debounce.
            [_debounceTimer invalidate];
            [_delegate semanticSearchBar:self queryDidChange:_queryField.stringValue];
            return YES;
        }
        if (cmd == @selector(cancelOperation:)) {
            [self close];
            return YES;
        }
    }
    return NO;
}

- (void)_darkModeChanged:(NSNotification *)n {
    self.layer.backgroundColor = [NppThemeManager shared].statusBarBackground.CGColor;
}

@end
