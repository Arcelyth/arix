pub const Rect = @import("geometry/Rect.zig");
pub const EdgeSizes = @import("geometry/EdgeSizes.zig");
pub const Point = [2]f64;
pub const Quad = [4]Point;
pub const Polygon = @import("geometry/Polygon.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
