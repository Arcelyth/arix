const std = @import("std");
const core = @import("core_foundation_zig");
const cg = core.core_graphics;
const cf = core.core_foundation;
const Rect = @import("../../geometry/Rect.zig");
const TextDisplayItem = @import("../display/display_item.zig").TextDisplayItem;

/// Premultiplied sRGB RGBA pixels, with the top row first.
pub const Bitmap = struct {
    pixels: [][4]u8,
    width: usize,
    height: usize,
    x: usize,
    y: usize,

    fn init(allocator: std.mem.Allocator, clip: Rect) !Bitmap {
        const x: usize = @intFromFloat(@floor(clip.x));
        const y: usize = @intFromFloat(@floor(clip.y));
        const right: usize = @intFromFloat(@ceil(clip.x + clip.width));
        const bottom: usize = @intFromFloat(@ceil(clip.y + clip.height));
        const pixels = try allocator.alloc([4]u8, try std.math.mul(usize, right - x, bottom - y));
        @memset(pixels, .{ 0, 0, 0, 0 });
        return .{
            .pixels = pixels,
            .width = right - x,
            .height = bottom - y,
            .x = x,
            .y = y,
        };
    }

    pub fn deinit(self: Bitmap, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }
};

pub fn rasterize(allocator: std.mem.Allocator, text: TextDisplayItem, clip: Rect, scale: f64) !Bitmap {
    const bitmap = try Bitmap.init(allocator, clip);
    errdefer bitmap.deinit(allocator);
    const space = try cg.CGColorSpace.initWithName(cf.CFString.fromRef(core.raw.kCGColorSpaceSRGB));
    defer space.deinit();

    const context = try cg.CGContext.initBitmap(
        std.mem.sliceAsBytes(bitmap.pixels),
        bitmap.width,
        bitmap.height,
        8,
        try std.math.mul(usize, bitmap.width, @sizeOf([4]u8)),
        space,
        core.raw.kCGImageAlphaPremultipliedLast | core.raw.kCGBitmapByteOrder32Big,
    );
    defer context.deinit();
    configure(context, bitmap, text, clip, scale);
    try drawGlyphs(allocator, context, text);

    return bitmap;
}

fn configure(context: cg.CGContext, bitmap: Bitmap, text: TextDisplayItem, clip: Rect, scale: f64) void {
    const x: f64 = @floatFromInt(bitmap.x);
    const y: f64 = @floatFromInt(bitmap.y);
    const height: f64 = @floatFromInt(bitmap.height);
    // Quartz uses a bottom-left origin; the destination canvas uses a top-left origin.
    context.clipToRect(.{
        .origin = .{
            .x = clip.x - x,
            .y = height - (clip.y + clip.height - y),
        },
        .size = .{
            .width = clip.width,
            .height = clip.height,
        },
    });
    context.translateCTM(
        text.baseline_origin[0] * scale - x,
        height - (text.baseline_origin[1] * scale - y),
    );
    context.scaleCTM(scale, scale);
    // Use grayscale antialiasing on transparency. Global alpha also applies to color glyphs.
    context.setShouldSmoothFonts(false);
    context.setRGBFillColor(text.color[0], text.color[1], text.color[2], 1);
    context.setAlpha(text.color[3]);
}

fn drawGlyphs(allocator: std.mem.Allocator, context: cg.CGContext, text: TextDisplayItem) !void {
    const ids = try allocator.alloc(cg.types.CGGlyph, text.glyphs.len);
    defer allocator.free(ids);
    const positions = try allocator.alloc(cg.geometry.CGPoint, text.glyphs.len);
    defer allocator.free(positions);

    for (text.glyphs, ids, positions) |glyph, *id, *position| {
        id.* = glyph.id;
        position.* = .{ .x = glyph.position[0], .y = glyph.position[1] };
    }
    // CTFontDrawGlyphs takes user-space origins and applies the font's matrix to glyph outlines.
    const matrix = text.text_matrix;
    const font = text.font.native.copyWithAttributes(0, .{
        .a = matrix[0][0],
        .b = matrix[0][1],
        .c = matrix[1][0],
        .d = matrix[1][1],
        .tx = 0,
        .ty = 0,
    }, null);
    defer font.deinit();
    try font.drawGlyphs(ids, positions, context);
}
