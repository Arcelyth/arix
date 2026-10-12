const std = @import("std");
const backend = @import("platform.zig").backend;
pub const ShapedText = @import("ShapedText.zig");
pub const Direction = ShapedText.Direction;

pub fn shape(allocator: std.mem.Allocator, text: []const u8, font: backend.Font, direction: Direction) !ShapedText {
    return backend.shape(allocator, text, font, direction);
}
