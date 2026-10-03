const Rect = @import("../../geometry/Rect.zig");

pub const DisplayItem = union(enum) {
    rect: RectDisplayItem,
};

pub const RectDisplayItem = struct {
    /// CSS pixels in canvas coordinates.
    rect: Rect,
    /// Unpremultiplied sRGB and alpha, each in [0, 1].
    color: [4]f64,
};
