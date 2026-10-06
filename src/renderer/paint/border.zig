const Canvas = @import("Canvas.zig");
const Border = @import("display/display_item.zig").BorderDisplayItem;
const Rect = @import("../geometry/Rect.zig");
const rasterization = @import("rasterization.zig");
const compositing = @import("compositing.zig");

pub fn draw(canvas: *Canvas, border: Border) !void {
    const clip = clippedBounds(canvas, border) orelse return;
    if (!border.details.radius.isZero()) return error.UnsupportedBorderRadius;
    const colors = try sideColors(border);
    const inner = innerBounds(border);
    const quads = sideQuads(border.bounds, inner);
    drawPixels(
        canvas,
        clip,
        inner,
        quads,
        colors,
    );
}

fn clippedBounds(canvas: *const Canvas, border: Border) ?Rect {
    const bounds = border.bounds.intersection(border.common.clip_rect) orelse return null;
    return bounds.intersection(.{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(canvas.width),
        .height = @floatFromInt(canvas.height),
    });
}

fn sideColors(border: Border) ![4][4]f64 {
    const details = border.details;
    var colors: [4][4]f64 = @splat(.{ 0, 0, 0, 0 });
    inline for (.{ "top", "right", "bottom", "left" }, 0..) |name, i| {
        const side = @field(details, name);
        if (@field(border.widths, name) > 0 and side.isVisible()) {
            if (side.style != .solid) return error.UnsupportedBorderStyle;
            colors[i] = side.color;
        }
    }
    return colors;
}

fn innerBounds(border: Border) Rect {
    return .{
        .x = border.bounds.x + border.widths.left,
        .y = border.bounds.y + border.widths.top,
        .width = border.bounds.width - border.widths.left - border.widths.right,
        .height = border.bounds.height - border.widths.top - border.widths.bottom,
    };
}

/// Use diagonal joins within the CSS corner transition area.
/// https://www.w3.org/TR/css-backgrounds-3/#corner-transitions
fn sideQuads(outer_bounds: Rect, inner_bounds: Rect) [4]rasterization.Quad {
    const outer = corners(outer_bounds);
    const inner = corners(inner_bounds);
    var quads: [4]rasterization.Quad = undefined;
    for (&quads, 0..) |*quad, i| {
        const next = (i + 1) % 4;
        quad.* = .{ outer[i], outer[next], inner[next], inner[i] };
    }
    return quads;
}

fn drawPixels(
    canvas: *Canvas,
    clip: Rect,
    inner: Rect,
    quads: [4]rasterization.Quad,
    colors: [4][4]f64,
) void {
    const x0: usize = @intFromFloat(@floor(clip.x));
    const y0: usize = @intFromFloat(@floor(clip.y));
    const x1: usize = @intFromFloat(@ceil(clip.x + clip.width));
    const y1: usize = @intFromFloat(@ceil(clip.y + clip.height));
    for (y0..y1) |y| {
        const py: f64 = @floatFromInt(y);
        for (x0..x1) |x| {
            const px: f64 = @floatFromInt(x);
            if (px >= inner.x and px + 1 <= inner.x + inner.width and py >= inner.y and py + 1 <= inner.y + inner.height) continue;
            const pixel = &canvas.pixels[y * canvas.width + x];
            compositing.sourceOver(pixel, pixelColor(quads, colors, px, py, clip));
        }
    }
}

/// Combine disjoint side contributions before source-over compositing.
fn pixelColor(
    quads: [4]rasterization.Quad,
    colors: [4][4]f64,
    x: f64,
    y: f64,
    clip: Rect,
) [4]f64 {
    var rgba: [4]f64 = @splat(0);
    for (quads, colors) |quad, color| {
        if (color[3] == 0) continue;
        const alpha = rasterization.quadCoverage(quad, x, y, clip) * color[3];
        for (0..3) |i| rgba[i] += color[i] * alpha;
        rgba[3] += alpha;
    }
    return rgba;
}

fn corners(rect: Rect) rasterization.Quad {
    return .{
        .{ rect.x, rect.y },
        .{ rect.x + rect.width, rect.y },
        .{ rect.x + rect.width, rect.y + rect.height },
        .{ rect.x, rect.y + rect.height },
    };
}
