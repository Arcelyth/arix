const std = @import("std");
const geometry = @import("../geometry.zig");
const Rect = geometry.Rect;
const Point = geometry.Point;
const Quad = geometry.Quad;
const Polygon = geometry.Polygon;

pub fn quadCoverage(
    quad: Quad,
    x: f64,
    y: f64,
    clip_rect: Rect,
) f64 {
    const lower = Point{
        @max(0, clip_rect.x - x),
        @max(0, clip_rect.y - y),
    };
    const upper = Point{
        @min(1, clip_rect.x + clip_rect.width - x),
        @min(1, clip_rect.y + clip_rect.height - y),
    };
    if (upper[0] <= lower[0] or upper[1] <= lower[1]) return 0;
    // Use pixel-local coordinates to keep polygon area arithmetic near zero.
    var local: Quad = undefined;
    for (quad, &local) |point, *dest|
        dest.* = .{ point[0] - x, point[1] - y };
    const polygon = Polygon.clipQuad(local, .{
        .x = lower[0],
        .y = lower[1],
        .width = upper[0] - lower[0],
        .height = upper[1] - lower[1],
    });
    return std.math.clamp(polygon.area(), 0, 1);
}
