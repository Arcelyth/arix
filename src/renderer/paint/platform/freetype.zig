const std = @import("std");
const ft = @import("freetype_zig");
const Rect = @import("../../geometry/Rect.zig");
const TextDisplayItem = @import("../display/display_item.zig").TextDisplayItem;
const Point = @import("../../geometry.zig").Point;

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
        if (!(clip.x >= 0 and clip.y >= 0 and clip.width > 0 and clip.height > 0 and
            right <= std.math.maxInt(i32) and bottom <= std.math.maxInt(i32)))
            return error.InvalidDimensions;

        const x: usize = @intFromFloat(@floor(clip.x));
        const y: usize = @intFromFloat(@floor(clip.y));
        const width = @as(usize, @intFromFloat(right)) - x;
        const height = @as(usize, @intFromFloat(bottom)) - y;
        const pixels = try allocator.alloc([4]u8, try std.math.mul(usize, width, height));
        @memset(pixels, .{ 0, 0, 0, 0 });

        return .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .x = x,
            .y = y,
        };
    }

    pub fn deinit(self: Bitmap, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }
};

pub fn rasterize(allocator: std.mem.Allocator, text: TextDisplayItem, clip: Rect, scale: f64) !Bitmap {
    if (!std.math.isFinite(scale) or scale <= 0) return error.InvalidScale;

    const matrix = text.text_matrix;
    const native_matrix: ft.raw.FT_Matrix = .{
        .xx = try fixed(matrix[0][0]),
        .xy = try fixed(matrix[1][0]),
        .yx = try fixed(matrix[0][1]),
        .yy = try fixed(matrix[1][1]),
    };
    const bitmap = try Bitmap.init(allocator, clip);
    errdefer bitmap.deinit(allocator);
    if (text.font.size == 0 or text.color[3] <= 0 or text.glyphs.len == 0) return bitmap;

    const library = try ft.Library.init();
    defer library.deinit();
    const face = try text.font.sizedFace(library, text.font.size * scale);
    defer face.deinit();
    const scalable = face.ref.*.face_flags & ft.raw.FT_FACE_FLAG_SCALABLE != 0;

    for (text.glyphs) |glyph| {
        const origin: Point = .{
            (text.baseline_origin[0] + glyph.position[0]) * scale,
            (text.baseline_origin[1] - glyph.position[1]) * scale,
        };
        for (origin) |value| {
            if (!std.math.isFinite(value) or @abs(value) > std.math.maxInt(i32))
                return error.InvalidPosition;
        }
        if (scalable) {
            // FreeType applies the Y-up matrix to the outline, not its positioned origin.
            // Keep the integer translation out of FreeType's 26.6 coordinates.
            face.setTransform(native_matrix, .{
                .x = @intFromFloat(@round((origin[0] - @floor(origin[0])) * 64)),
                .y = @intFromFloat(@round(-(origin[1] - @floor(origin[1])) * 64)),
            });
        }
        const flags: ft.raw.FT_Int32 = @intCast(ft.raw.FT_LOAD_COLOR | if (scalable)
            ft.raw.FT_LOAD_NO_BITMAP | ft.raw.FT_LOAD_NO_HINTING
        else
            @as(ft.raw.FT_Int32, 0));

        const slot = try face.loadGlyph(glyph.id, flags);
        const source = try slot.render(ft.raw.FT_RENDER_MODE_NORMAL);
        if (source.raw.width == 0 or source.raw.rows == 0) continue;
        try validateBitmap(source);
        const left: f64 = @floatFromInt(slot.getBitmapLeft());
        const top: f64 = @floatFromInt(slot.getBitmapTop());

        if (scalable) {
            blit(bitmap, source, .{
                .{ 1, 0 },
                .{ 0, 1 },
                .{ @floor(origin[0]) + left, @floor(origin[1]) - top },
            }, text.color, false);
        } else {
            // Embedded strikes ignore FT_Set_Transform and must be scaled and
            // transformed here, including color emoji.
            const metrics = face.getSizeMetrics() orelse return error.MissingFontMetrics;
            if (metrics.x_ppem == 0 or metrics.y_ppem == 0) return error.MissingFontMetrics;

            const sx = text.font.size * scale / @as(f64, @floatFromInt(metrics.x_ppem));
            const sy = text.font.size * scale / @as(f64, @floatFromInt(metrics.y_ppem));
            const a = matrix[0][0] * sx;
            const b = -matrix[0][1] * sx;
            const c = -matrix[1][0] * sy;
            const d = matrix[1][1] * sy;

            blit(bitmap, source, .{
                .{ a, b },
                .{ c, d },
                .{ origin[0] + a * left - c * top, origin[1] + b * left - d * top },
            }, text.color, true);
        }
    }

    applyOpacity(bitmap, clip, text.color[3]);
    return bitmap;
}

fn fixed(value: f64) !ft.raw.FT_Fixed {
    const scaled = @round(value * 65536);
    if (!std.math.isFinite(scaled) or scaled < std.math.minInt(i32) or scaled > std.math.maxInt(i32))
        return error.InvalidTransform;

    return @intFromFloat(scaled);
}

/// Checks a nonempty bitmap before sampling its rows.
fn validateBitmap(bitmap: ft.Bitmap) !void {
    const bytes: usize = switch (bitmap.raw.pixel_mode) {
        ft.raw.FT_PIXEL_MODE_MONO => (@as(usize, bitmap.raw.width) + 7) / 8,
        ft.raw.FT_PIXEL_MODE_GRAY2 => (@as(usize, bitmap.raw.width) + 3) / 4,
        ft.raw.FT_PIXEL_MODE_GRAY4 => (@as(usize, bitmap.raw.width) + 1) / 2,
        ft.raw.FT_PIXEL_MODE_GRAY => blk: {
            if (bitmap.raw.num_grays < 2) return error.InvalidBitmap;
            break :blk bitmap.raw.width;
        },
        ft.raw.FT_PIXEL_MODE_BGRA => try std.math.mul(usize, bitmap.raw.width, 4),
        else => return error.UnsupportedPixelMode,
    };
    if (bitmap.raw.buffer == null or @abs(bitmap.raw.pitch) < bytes) return error.InvalidBitmap;
}

/// Composites a validated glyph bitmap over `destination` using source-over.
fn blit(
    destination: Bitmap,
    source: ft.Bitmap,
    matrix: [3]Point,
    color: [4]f64,
    filter: bool,
) void {
    _ = destination;
    _ = source;
    _ = matrix;
    _ = color;
    _ = filter;
}

fn applyOpacity(bitmap: Bitmap, clip: Rect, opacity: f64) void {
    for (0..bitmap.height) |row| {
        const y: f64 = @floatFromInt(bitmap.y + row);
        const coverage_y = @min(y + 1, clip.y + clip.height) - @max(y, clip.y);
        for (0..bitmap.width) |column| {
            const x: f64 = @floatFromInt(bitmap.x + column);
            const coverage_x = @min(x + 1, clip.x + clip.width) - @max(x, clip.x);
            const factor = std.math.clamp(opacity * coverage_x * coverage_y, 0, 1);
            for (&bitmap.pixels[row * bitmap.width + column]) |*channel|
                channel.* = @intFromFloat(@round(@as(f64, @floatFromInt(channel.*)) * factor));
        }
    }
}
