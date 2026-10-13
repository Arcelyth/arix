const std = @import("std");
const Canvas = @import("Canvas.zig");
const Rect = @import("../geometry/Rect.zig");
const TextDisplayItem = @import("display/display_item.zig").TextDisplayItem;
const compositing = @import("compositing.zig");
const backend = switch (@import("builtin").os.tag) {
    .macos => @import("platform/core_graphics.zig"),
    else => @compileError("Text rasterization is not implemented for this platform"),
};

pub fn draw(allocator: std.mem.Allocator, canvas: *Canvas, text: TextDisplayItem) !void {
    if (text.glyphs.len == 0 or text.font.size == 0 or text.color[3] <= 0) return;
    const clip = deviceClip(canvas, text.common.clip_rect) orelse return;

    const bitmap = try backend.rasterize(allocator, text, clip, canvas.device_pixel_ratio);
    defer bitmap.deinit(allocator);
    composite(canvas, bitmap);
}

fn deviceClip(canvas: *const Canvas, clip: Rect) ?Rect {
    const scale = canvas.device_pixel_ratio;
    const scaled: Rect = .{
        .x = clip.x * scale,
        .y = clip.y * scale,
        .width = clip.width * scale,
        .height = clip.height * scale,
    };
    return scaled.intersection(.{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(canvas.width),
        .height = @floatFromInt(canvas.height),
    });
}

fn composite(canvas: *Canvas, bitmap: backend.Bitmap) void {
    for (0..bitmap.height) |y| {
        const row = bitmap.pixels[y * bitmap.width ..][0..bitmap.width];
        const destination = canvas.pixels[(bitmap.y + y) * canvas.width + bitmap.x ..][0..bitmap.width];
        compositing.sourceOverPixels(destination, row);
    }
}
