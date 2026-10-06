const std = @import("std");
const Rect = @import("../geometry/Rect.zig");
// TODO: Move to other module.
pub const Point = [2]f64;
pub const Quad = [4]Point;

const Polygon = struct {
    points: [8]Point = undefined,
    len: usize = 0,

    fn append(self: *Polygon, point: Point) void {
        self.points[self.len] = point;
        self.len += 1;
    }
};

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
    var polygon: Polygon = .{};
    for (quad) |point|
        polygon.append(.{ point[0] - x, point[1] - y });

    inline for (0..2) |axis| {
        polygon = clip(polygon, axis, lower[axis], true);
        polygon = clip(polygon, axis, upper[axis], false);
    }
    return std.math.clamp(polygonArea(polygon), 0, 1);
}

fn polygonArea(polygon: Polygon) f64 {
    if (polygon.len < 3) return 0;
    var area: f64 = 0;
    var previous = polygon.points[polygon.len - 1];
    for (polygon.points[0..polygon.len]) |point| {
        area += previous[0] * point[1] - previous[1] * point[0];
        previous = point;
    }
    return @abs(area) / 2;
}

fn clip(
    input: Polygon,
    axis: usize,
    boundary: f64,
    greater: bool,
) Polygon {
    var result: Polygon = .{};
    if (input.len == 0) return result;
    var previous = input.points[input.len - 1];
    var previous_inside = if (greater) previous[axis] >= boundary else previous[axis] <= boundary;

    for (input.points[0..input.len]) |point| {
        const inside = if (greater) point[axis] >= boundary else point[axis] <= boundary;
        if (inside != previous_inside) {
            const t = (boundary - previous[axis]) / (point[axis] - previous[axis]);
            result.append(.{
                previous[0] + t * (point[0] - previous[0]),
                previous[1] + t * (point[1] - previous[1]),
            });
        }
        if (inside) result.append(point);
        previous = point;
        previous_inside = inside;
    }
    return result;
}
