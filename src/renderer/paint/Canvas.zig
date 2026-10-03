const Canvas = @This();

const std = @import("std");
const Rect = @import("../geometry/Rect.zig");
const DisplayList = @import("display/DisplayList.zig");

pub const Pixel = [3]u8;

width: usize,
height: usize,
pixels: []Pixel,

/// One raster pixel per CSS pixel, initialized to a white surface.
pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Canvas {
    if (width == 0 or height == 0) return error.InvalidDimensions;
    const pixels = try allocator.alloc(Pixel, try std.math.mul(usize, width, height));
    @memset(pixels, .{ 255, 255, 255 });
    return .{ .width = width, .height = height, .pixels = pixels };
}

pub fn deinit(self: *Canvas, allocator: std.mem.Allocator) void {
    allocator.free(self.pixels);
    self.pixels = &.{};
    self.width = 0;
    self.height = 0;
}

pub fn draw(self: *Canvas, list: *const DisplayList) void {
    for (list.items.items) |item| switch (item) {
        .rect => |command| self.fillRect(command.rect, command.color),
    };
}

pub fn fillRect(self: *Canvas, rect: Rect, rgba: [4]f64) void {
    if (rgba[3] == 0 or rect.width <= 0 or rect.height <= 0) return;

    const left = std.math.clamp(
        rect.x,
        0,
        @as(f64, @floatFromInt(self.width)),
    );
    const top = std.math.clamp(
        rect.y,
        0,
        @as(f64, @floatFromInt(self.height)),
    );
    const right = std.math.clamp(
        rect.x + rect.width,
        0,
        @as(f64, @floatFromInt(self.width)),
    );
    const bottom = std.math.clamp(
        rect.y + rect.height,
        0,
        @as(f64, @floatFromInt(self.height)),
    );

    if (left >= right or top >= bottom) return;
    const x0: usize = @intFromFloat(@floor(left));
    const y0: usize = @intFromFloat(@floor(top));
    const x1: usize = @intFromFloat(@ceil(right));
    const y1: usize = @intFromFloat(@ceil(bottom));
    const rgb: Pixel = .{
        @intFromFloat(@round(rgba[0] * 255)),
        @intFromFloat(@round(rgba[1] * 255)),
        @intFromFloat(@round(rgba[2] * 255)),
    };

    // Fast path which coverage is not be handled.
    if (rgba[3] == 1 and
        left == @floor(left) and
        top == @floor(top) and
        right == @floor(right) and
        bottom == @floor(bottom))
    {
        for (y0..y1) |y| @memset(self.pixels[y * self.width + x0 .. y * self.width + x1], rgb);
        return;
    }
    @panic("TODO: alpha compositing and coverage handling");
}
