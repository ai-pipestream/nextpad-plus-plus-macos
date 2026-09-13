#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace SemanticHeatmap {

// -1: stricter matches, 0: original ramp, 1: broader matches.
inline uint32_t colorBGR(double score, int sensitivity = 0) {
    static constexpr struct { double score; int r, g, b; } stops[] = {
        {0.00, 0xD6, 0x45, 0x41},
        {0.35, 0xD6, 0x45, 0x41},
        {0.60, 0xB2, 0x69, 0x64},
        {0.72, 0x8E, 0x8E, 0x8E},
        {0.78, 0x8E, 0x8E, 0x8E},
        {0.90, 0x2E, 0xCC, 0x71},
        {0.93, 0x0B, 0x8A, 0x45},
        {1.00, 0x0B, 0x8A, 0x45},
    };
    if (!std::isfinite(score)) return 0x8E8E8E;
    double t = std::clamp(score, 0.0, 1.0);
    t = std::pow(t, sensitivity < 0 ? 1.4 : sensitivity > 0 ? 0.7 : 1.0);
    for (unsigned i = 1; i < sizeof(stops) / sizeof(stops[0]); ++i) {
        if (t > stops[i].score) continue;
        const auto &a = stops[i - 1];
        const auto &b = stops[i];
        const double f = (t - a.score) / (b.score - a.score);
        const int r = static_cast<int>(a.r + (b.r - a.r) * f);
        const int g = static_cast<int>(a.g + (b.g - a.g) * f);
        const int blue = static_cast<int>(a.b + (b.b - a.b) * f);
        return static_cast<uint32_t>((blue << 16) | (g << 8) | r);
    }
    return 0x458A0B;
}

} // namespace SemanticHeatmap
