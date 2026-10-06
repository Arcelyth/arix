const std = @import("std");
const Canvas = @import("Canvas.zig");
const BorderDisplayItem = @import("display/display_item.zig").BorderDisplayItem;

pub fn draw(canvas: *Canvas, border: BorderDisplayItem) !void {
    _ = canvas;
    _ = border;
}
