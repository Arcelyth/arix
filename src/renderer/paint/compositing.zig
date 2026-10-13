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

/// Composite premultiplied 8-bit RGBA pixels over equally many RGB pixels.
pub fn sourceOverPixels(destination: [][3]u8, source: []const [4]u8) void {
    std.debug.assert(destination.len == source.len);

    for (destination, source) |*pixel, rgba| {
        if (rgba[3] == 0) continue;
        var normalized: [4]f64 = undefined;
        for (&normalized, rgba) |*channel, byte| channel.* = @as(f64, @floatFromInt(byte)) / 255;
        sourceOver(pixel, normalized);
    }
}
