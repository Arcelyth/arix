//! A convex polygon produced by clipping a quadrilateral to a rectangle.
const Polygon = @This();
const geometry = @import("../geometry.zig");
const Point = geometry.Point;
const Quad = geometry.Quad;
const Rect = geometry.Rect;

/// Corners in boundary order. Clipping can produce at most eight corners.
points: [8]Point = undefined,
/// Number of used entries in `points`.
len: usize = 0,

/// Keep the part of a convex quad inside `bounds`.
/// Quad corners must follow the boundary, in either direction.
pub fn clipQuad(quad: Quad, bounds: Rect) Polygon {
    if (bounds.width <= 0 or bounds.height <= 0) return .{};
    var polygon: Polygon = .{};
    for (quad) |point| polygon.append(point);
    polygon = polygon.clip(0, bounds.x, true);
    polygon = polygon.clip(0, bounds.x + bounds.width, false);
    polygon = polygon.clip(1, bounds.y, true);
    return polygon.clip(1, bounds.y + bounds.height, false);
}

/// Return the area for clockwise or counterclockwise corners.
/// Fewer than three corners give zero.
pub fn area(self: Polygon) f64 {
    if (self.len < 3) return 0;
    var sum: f64 = 0;
    var previous = self.points[self.len - 1];
    // Sum each edge's contribution, including the closing edge.
    for (self.points[0..self.len]) |point| {
        sum += previous[0] * point[1] - previous[1] * point[0];
        previous = point;
    }
    return @abs(sum) / 2;
}

fn append(self: *Polygon, point: Point) void {
    self.points[self.len] = point;
    self.len += 1;
}

/// Cut along one boundary: axis 0 is x, axis 1 is y.
/// Keep coordinates >= boundary when `greater` is true, otherwise <= boundary.
pub fn clip(self: Polygon, axis: usize, boundary: f64, greater: bool) Polygon {
    var result: Polygon = .{};
    if (self.len == 0) return result;
    var previous = self.points[self.len - 1];
    var previous_inside = if (greater) previous[axis] >= boundary else previous[axis] <= boundary;
    for (self.points[0..self.len]) |point| {
        const inside = if (greater) point[axis] >= boundary else point[axis] <= boundary;
        if (inside != previous_inside) {
            // The edge crosses the boundary; add its intersection point.
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

test "geometry Polygon: clipped quad area and winding" {
    const testing = @import("std").testing;
    const diamond: Quad = .{
        .{ -1, 2 },
        .{ 2, -1 },
        .{ 5, 2 },
        .{ 2, 5 },
    };
    const bounds: Rect = .{ .x = 0, .y = 0, .width = 4, .height = 4 };
    const clipped = clipQuad(diamond, bounds);
    try testing.expectEqual(@as(usize, 8), clipped.len);
    try testing.expectEqual(@as(f64, 14), clipped.area());

    const reversed: Quad = .{ diamond[3], diamond[2], diamond[1], diamond[0] };
    try testing.expectEqual(clipped.area(), clipQuad(reversed, bounds).area());
    try testing.expectEqual(@as(f64, 16), clipQuad(bounds.corners(), bounds).area());
    try testing.expectEqual(@as(f64, 0), clipQuad(diamond, .{
        .x = 10,
        .y = 10,
        .width = 1,
        .height = 1,
    }).area());
    try testing.expectEqual(@as(f64, 0), clipQuad(diamond, .{ .x = 0, .y = 0, .width = 0, .height = 4 }).area());
}
