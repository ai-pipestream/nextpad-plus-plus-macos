#undef NDEBUG
#include "SemanticHeatmapColors.h"
#include <cassert>
#include <limits>

int main() {
    using SemanticHeatmap::colorBGR;
    // Preserve the original default ramp and Scintilla's channel order.
    assert(colorBGR(0.0) == 0x4145D6);
    assert(colorBGR(0.35) == 0x4145D6);
    assert(colorBGR(0.60) == 0x6469B2);
    assert(colorBGR(0.75) == 0x8E8E8E);
    assert(colorBGR(0.90) == 0x71CC2E);
    assert(colorBGR(0.93) == 0x458A0B);
    assert(colorBGR(1.0) == 0x458A0B);
    for (int sensitivity : {-1, 0, 1}) {
        assert(colorBGR(-1.0, sensitivity) == colorBGR(0.0, sensitivity));
        assert(colorBGR(2.0, sensitivity) == colorBGR(1.0, sensitivity));
        assert(colorBGR(std::numeric_limits<double>::quiet_NaN(), sensitivity) == 0x8E8E8E);
        assert(colorBGR(std::numeric_limits<double>::infinity(), sensitivity) == 0x8E8E8E);
    }
    // The same intermediate score becomes redder in Strict and greener in Broad.
    auto greenMinusRed = [](uint32_t bgr) {
        return static_cast<int>((bgr >> 8) & 255) - static_cast<int>(bgr & 255);
    };
    assert(greenMinusRed(colorBGR(0.75, -1)) < 0);
    assert(greenMinusRed(colorBGR(0.75, 0)) == 0);
    assert(greenMinusRed(colorBGR(0.75, 1)) > 0);
}
