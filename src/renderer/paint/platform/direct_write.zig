const std = @import("std");
const dw = @import("dwrite_zig");
const Rect = @import("../../geometry/Rect.zig");
const TextDisplayItem = @import("../display/display_item.zig").TextDisplayItem;

const texture_type = dw.raw.DWRITE_TEXTURE_CLEARTYPE_3x1;

/// Premultiplied sRGB RGBA pixels, with the top row first.
pub const Bitmap = struct {
    pixels: [][4]u8,
    width: usize,
    height: usize,
    x: usize,
    y: usize,

    fn init(allocator: std.mem.Allocator, clip: Rect) !Bitmap {
        const right = @ceil(clip.x + clip.width);
        const bottom = @ceil(clip.y + clip.height);
        const limit: f64 = std.math.maxInt(i32);
        if (!(clip.x >= 0 and clip.y >= 0 and right <= limit and bottom <= limit))
            return error.InvalidDimensions;
        const x: usize = @intFromFloat(@floor(clip.x));
        const y: usize = @intFromFloat(@floor(clip.y));
        const width = @as(usize, @intFromFloat(right)) - x;
        const height = @as(usize, @intFromFloat(bottom)) - y;
        const pixels = try allocator.alloc([4]u8, try std.math.mul(usize, width, height));
        @memset(pixels, .{ 0, 0, 0, 0 });
        return .{ .pixels = pixels, .width = width, .height = height, .x = x, .y = y };
    }

    pub fn deinit(self: Bitmap, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }
};

pub fn rasterize(allocator: std.mem.Allocator, text: TextDisplayItem, clip: Rect, scale: f64) !Bitmap {
    const pixels_per_dip: f32 = @floatCast(scale);
    if (!std.math.isFinite(pixels_per_dip) or pixels_per_dip <= 0) return error.InvalidScale;
    const bitmap = try Bitmap.init(allocator, clip);
    errdefer bitmap.deinit(allocator);
    const factory = try dw.Factory.init(dw.raw.DWRITE_FACTORY_TYPE_SHARED);
    defer factory.deinit();
    var coverage: std.ArrayList(u8) = .empty;
    defer coverage.deinit(allocator);

    for (text.glyphs) |glyph| {
        const analysis = try analyzeGlyph(factory, text, glyph, pixels_per_dip);
        defer analysis.deinit();
        const bounds = clippedBounds(try analysis.getAlphaTextureBounds(texture_type), bitmap) orelse continue;
        const width: usize = @intCast(bounds.right - bounds.left);
        const height: usize = @intCast(bounds.bottom - bounds.top);
        const size = try std.math.mul(usize, try std.math.mul(usize, width, height), 3);
        if (size > std.math.maxInt(u32)) return error.InputTooLong;
        try coverage.resize(allocator, size);
        try analysis.createAlphaTexture(texture_type, bounds, coverage.items);
        accumulateCoverage(bitmap, bounds, coverage.items);
    }
    colorize(bitmap, text.color, clip);

    return bitmap;
}

fn analyzeGlyph(factory: dw.Factory, text: TextDisplayItem, glyph: TextDisplayItem.Glyph, scale: f32) !dw.GlyphRunAnalysis {
    const matrix = text.text_matrix;
    // Convert the outline matrix from Y-up to Y-down. Glyph origins are already
    // positioned by shaping. Apply the matrix only to each glyph's outline.
    const transform: dw.raw.DWRITE_MATRIX = .{
        .m11 = @floatCast(matrix[0][0]),
        .m12 = @floatCast(-matrix[0][1]),
        .m21 = @floatCast(-matrix[1][0]),
        .m22 = @floatCast(matrix[1][1]),
        .dx = @floatCast((text.baseline_origin[0] + glyph.position[0]) * scale),
        .dy = @floatCast((text.baseline_origin[1] - glyph.position[1]) * scale),
    };
    const advance: f32 = 0;

    return factory.createGlyphRunAnalysis(&.{
        .fontFace = text.font.native.ref,
        .fontEmSize = @floatCast(text.font.size),
        .glyphCount = 1,
        .glyphIndices = &glyph.id,
        .glyphAdvances = &advance,
        .glyphOffsets = null,
        .isSideways = 0,
        .bidiLevel = 0,
    }, .{
        .pixels_per_dip = scale,
        .transform = &transform,
        .rendering_mode = dw.raw.DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC,
    });
}

fn clippedBounds(bounds: dw.raw.RECT, bitmap: Bitmap) ?dw.raw.RECT {
    const result: dw.raw.RECT = .{
        .left = @max(bounds.left, @as(i32, @intCast(bitmap.x))),
        .top = @max(bounds.top, @as(i32, @intCast(bitmap.y))),
        .right = @min(bounds.right, @as(i32, @intCast(bitmap.x + bitmap.width))),
        .bottom = @min(bounds.bottom, @as(i32, @intCast(bitmap.y + bitmap.height))),
    };

    return if (result.right > result.left and result.bottom > result.top) result else null;
}

fn accumulateCoverage(bitmap: Bitmap, bounds: dw.raw.RECT, coverage: []const u8) void {
    const x: usize = @intCast(bounds.left);
    const y: usize = @intCast(bounds.top);
    const width: usize = @intCast(bounds.right - bounds.left);
    const height: usize = @intCast(bounds.bottom - bounds.top);
    for (0..height) |row| {
        for (0..width) |column| {
            const sample = coverage[(row * width + column) * 3 ..][0..3];
            // Collapse subpixel coverage to neutral coverage for the transparent
            // bitmap. This is an approximation of grayscale antialiasing.
            const alpha: u32 = (@as(u32, sample[0]) + sample[1] + sample[2] + 1) / 3;
            const pixel = &bitmap.pixels[(y - bitmap.y + row) * bitmap.width + x - bitmap.x + column];
            pixel[3] = @intCast(255 - ((255 - @as(u32, pixel[3])) * (255 - alpha) + 127) / 255);
        }
    }
}

fn colorize(bitmap: Bitmap, color: [4]f64, clip: Rect) void {
    for (0..bitmap.height) |row| {
        const y: f64 = @floatFromInt(bitmap.y + row);
        const coverage_y = @min(y + 1, clip.y + clip.height) - @max(y, clip.y);
        for (0..bitmap.width) |column| {
            const x: f64 = @floatFromInt(bitmap.x + column);
            const coverage_x = @min(x + 1, clip.x + clip.width) - @max(x, clip.x);
            const pixel = &bitmap.pixels[row * bitmap.width + column];
            const alpha = @as(f64, @floatFromInt(pixel[3])) * color[3] * coverage_x * coverage_y;
            for (0..3) |channel| pixel[channel] = @intFromFloat(@round(color[channel] * alpha));
            pixel[3] = @intFromFloat(@round(alpha));
        }
    }
}
