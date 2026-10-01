pub const Rect = @import("geometry/Rect.zig");
pub const EdgeSizes = @import("geometry/EdgeSizes.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
