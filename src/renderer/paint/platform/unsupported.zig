const std = @import("std");
const Rect = @import("../../geometry/Rect.zig");
const TextDisplayItem = @import("../display/display_item.zig").TextDisplayItem;

pub const Bitmap = struct {
    pixels: [][4]u8 = &.{},
    width: usize = 0,
    height: usize = 0,
    x: usize = 0,
    y: usize = 0,

    pub fn deinit(_: Bitmap, _: std.mem.Allocator) void {}
};

/// Text painting is a no-op until this platform has a rasterizer.
pub fn rasterize(_: std.mem.Allocator, _: TextDisplayItem, _: Rect, _: f64) !Bitmap {
    return .{};
}
