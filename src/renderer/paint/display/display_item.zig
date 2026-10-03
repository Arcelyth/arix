const Rect = @import("../../geometry/Rect.zig");

pub const DisplayItem = union(enum) {
    rect: RectDisplayItem,
};

pub const RectDisplayItem = struct {
    rect: Rect,
    color: [4]f64,
};
