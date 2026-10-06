const Rect = @This();

x: f64,
y: f64,
width: f64,
height: f64,

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
