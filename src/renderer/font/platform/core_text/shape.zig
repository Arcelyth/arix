const std = @import("std");
const core = @import("core_foundation_zig");
const cf = core.core_foundation;
const ct = core.core_text;
const Font = @import("Font.zig");
const ShapedText = @import("../../ShapedText.zig");
const Direction = ShapedText.Direction;

pub fn shape(
    allocator: std.mem.Allocator,
    text: []const u8,
    font: Font,
    direction: Direction,
) !ShapedText {
    _ = allocator;
    _ = text;
    _ = font;
    _ = direction;
}
