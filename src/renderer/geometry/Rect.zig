const Rect = @This();
const Quad = @import("../geometry.zig").Quad;

x: f64,
y: f64,
width: f64,
height: f64,

/// Return the four corners of the rectangle in clockwise order.
pub fn corners(self: Rect) Quad {
    return .{
        .{ self.x, self.y },
        .{ self.x + self.width, self.y },
        .{ self.x + self.width, self.y + self.height },
        .{ self.x, self.y + self.height },
    };
}

/// Return the overlapping rectangle, or null if there is no overlap.
pub fn intersection(self: Rect, other: Rect) ?Rect {
    const left = @max(self.x, other.x);
    const top = @max(self.y, other.y);
    const right = @min(self.x + self.width, other.x + other.width);
    const bottom = @min(self.y + self.height, other.y + other.height);

    if (right <= left or bottom <= top) return null;
    return .{
        .x = left,
        .y = top,
        .width = right - left,
        .height = bottom - top,
    };
}
