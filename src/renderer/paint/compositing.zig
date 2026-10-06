const std = @import("std");

/// Composite premultiplied RGBA over an opaque 8-bit RGB destination.
/// https://www.w3.org/TR/compositing-1/#porterduffcompositingoperators_srcover
pub fn sourceOver(destination: *[3]u8, source: [4]f64) void {
    const remaining = 1 - std.math.clamp(source[3], 0, 1);
    for (destination, 0..) |*channel, i| {
        const value = source[i] * 255 + @as(f64, @floatFromInt(channel.*)) * remaining;
        channel.* = @intFromFloat(@round(std.math.clamp(value, 0, 255)));
    }
}
