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

/// Reads one validated bitmap pixel as normalized premultiplied sRGB RGBA.
/// Out-of-bounds coordinates yield transparent black.
fn sample(bitmap: ft.Bitmap, x: i64, y: i64, color: [4]f64) [4]f64 {
    if (x < 0 or y < 0 or x >= bitmap.raw.width or y >= bitmap.raw.rows) return .{ 0, 0, 0, 0 };
    const column: usize = @intCast(x);
    const row = bitmap.row(@intCast(y));
    if (bitmap.raw.pixel_mode == ft.raw.FT_PIXEL_MODE_BGRA) {
        const pixel = row[column * 4 ..][0..4];
        return .{
            @as(f64, @floatFromInt(pixel[2])) / 255,
            @as(f64, @floatFromInt(pixel[1])) / 255,
            @as(f64, @floatFromInt(pixel[0])) / 255,
            @as(f64, @floatFromInt(pixel[3])) / 255,
        };
    }
    const alpha: f64 = switch (bitmap.raw.pixel_mode) {
        ft.raw.FT_PIXEL_MODE_MONO => @floatFromInt((row[column / 8] >> @as(u3, @intCast(7 - column % 8))) & 1),
        ft.raw.FT_PIXEL_MODE_GRAY2 => @as(f64, @floatFromInt((row[column / 4] >> @as(u3, @intCast(6 - column % 4 * 2))) & 3)) / 3,
        ft.raw.FT_PIXEL_MODE_GRAY4 => @as(f64, @floatFromInt((row[column / 2] >> @as(u3, @intCast(4 - column % 2 * 4))) & 15)) / 15,
        ft.raw.FT_PIXEL_MODE_GRAY => @as(f64, @floatFromInt(row[column])) / @as(f64, @floatFromInt(bitmap.raw.num_grays - 1)),
        else => unreachable,
    };

    return .{
        color[0] * alpha,
        color[1] * alpha,
        color[2] * alpha,
        alpha,
    };
}

/// Bilinearly samples a validated bitmap with transparent pixels outside its bounds.
/// Coordinates refer to pixel edges, placing the first pixel center at (0.5, 0.5).
/// Interpolation uses premultiplied channels to avoid color fringes at transparent edges.
fn filteredSample(bitmap: ft.Bitmap, x: f64, y: f64, color: [4]f64) [4]f64 {
    if (!(x > -1 and y > -1 and x < @as(f64, @floatFromInt(bitmap.raw.width)) + 1 and
        y < @as(f64, @floatFromInt(bitmap.raw.rows)) + 1)) return .{ 0, 0, 0, 0 };

    const px = x - 0.5;
    const py = y - 0.5;
    const ix: i64 = @intFromFloat(@floor(px));
    const iy: i64 = @intFromFloat(@floor(py));
    const fx = px - @floor(px);
    const fy = py - @floor(py);
    var result: [4]f64 = @splat(0);
    for (0..2) |row| {
        for (0..2) |column| {
            const weight = (if (column == 0) 1 - fx else fx) * (if (row == 0) 1 - fy else fy);
            const value = sample(bitmap, ix + @as(i64, @intCast(column)), iy + @as(i64, @intCast(row)), color);
            for (&result, value) |*channel, v| channel.* += v * weight;
        }
    }

    return result;
}

/// Composites a validated glyph bitmap over `destination` using source-over.
fn blit(
    destination: Bitmap,
    source: ft.Bitmap,
    matrix: [3]Point,
    color: [4]f64,
    filter: bool,
) void {
    const a = matrix[0][0];
    const b = matrix[0][1];
    const c = matrix[1][0];
    const d = matrix[1][1];
    const det = a * d - b * c;
    if (det == 0 or !std.math.isFinite(det)) return;

    const width: f64 = @floatFromInt(source.raw.width);
    const height: f64 = @floatFromInt(source.raw.rows);
    var lower: Point = .{ std.math.inf(f64), std.math.inf(f64) };
    var upper: Point = .{ -std.math.inf(f64), -std.math.inf(f64) };
    const pad: f64 = if (filter) 0.5 else 0;
    for ([_]f64{ -pad, height + pad }) |y| {
        for ([_]f64{ -pad, width + pad }) |x| {
            const point: Point = .{ a * x + c * y + matrix[2][0], b * x + d * y + matrix[2][1] };
            for (0..2) |i| {
                lower[i] = @min(lower[i], point[i]);
                upper[i] = @max(upper[i], point[i]);
            }
        }
    }

    const left: f64 = @floatFromInt(destination.x);
    const top: f64 = @floatFromInt(destination.y);
    const right: f64 = @floatFromInt(destination.x + destination.width);
    const bottom: f64 = @floatFromInt(destination.y + destination.height);
    const x0: usize = @intFromFloat(std.math.clamp(@floor(lower[0]), left, right));
    const y0: usize = @intFromFloat(std.math.clamp(@floor(lower[1]), top, bottom));
    const x1: usize = @intFromFloat(std.math.clamp(@ceil(upper[0]), left, right));
    const y1: usize = @intFromFloat(std.math.clamp(@ceil(upper[1]), top, bottom));
    // Supersample embedded bitmaps when shrinking or transforming their pixels.
    const samples: usize = if (filter) 4 else 1;
    const count: f64 = @floatFromInt(samples);

    for (y0..y1) |y| {
        for (x0..x1) |x| {
            var rgba: [4]f64 = @splat(0);
            for (0..samples) |sy| {
                for (0..samples) |sx| {
                    const dx = @as(f64, @floatFromInt(x)) + (@as(f64, @floatFromInt(sx)) + 0.5) / count - matrix[2][0];
                    const dy = @as(f64, @floatFromInt(y)) + (@as(f64, @floatFromInt(sy)) + 0.5) / count - matrix[2][1];
                    const px = (d * dx - c * dy) / det;
                    const py = (a * dy - b * dx) / det;
                    const value = if (filter) filteredSample(source, px, py, color) else sample(source, @intFromFloat(@floor(px)), @intFromFloat(@floor(py)), color);
                    for (&rgba, value) |*channel, v| channel.* += v / (count * count);
                }
            }
            const pixel = &destination.pixels[(y - destination.y) * destination.width + x - destination.x];
            for (pixel, rgba) |*channel, value|
                channel.* = @intFromFloat(@round(std.math.clamp(value * 255 + @as(f64, @floatFromInt(channel.*)) * (1 - rgba[3]), 0, 255)));
        }
    }
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
