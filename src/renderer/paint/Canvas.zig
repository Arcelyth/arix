const Canvas = @This();

const std = @import("std");
const Rect = @import("../geometry/Rect.zig");
const DisplayList = @import("display/DisplayList.zig");
const border = @import("border.zig");
const compositing = @import("compositing.zig");

pub const Pixel = [3]u8;
pub const Options = struct {
    clear_color: Pixel,
    device_pixel_ratio: f64 = 1,
};

width: usize,
height: usize,
pixels: []Pixel,
device_pixel_ratio: f64,

pub fn init(
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    options: Options,
) !Canvas {
    if (width == 0 or height == 0) return error.InvalidDimensions;
    if (!std.math.isFinite(options.device_pixel_ratio) or options.device_pixel_ratio <= 0) return error.InvalidScale;

    const pixels = try allocator.alloc(Pixel, try std.math.mul(usize, width, height));
    @memset(pixels, options.clear_color);
    return .{ .width = width, .height = height, .pixels = pixels, .device_pixel_ratio = options.device_pixel_ratio };
}

pub fn deinit(self: *Canvas, allocator: std.mem.Allocator) void {
    allocator.free(self.pixels);
    self.pixels = &.{};
    self.width = 0;
    self.height = 0;
}

pub fn draw(self: *Canvas, list: *const DisplayList) !void {
    for (list.items.items) |item| switch (item) {
        .rect => |command| {
            const bounds = command.bounds.intersection(command.common.clip_rect) orelse continue;
            self.fillRect(self.scaleRect(bounds), command.color);
        },
        .border => |command| {
            var scaled = command;
            scaled.bounds = self.scaleRect(command.bounds);
            scaled.common.clip_rect = self.scaleRect(command.common.clip_rect);
            inline for (.{ "top", "right", "bottom", "left" }) |side| {
                @field(scaled.widths, side) *= self.device_pixel_ratio;
            }
            inline for (.{ "top_left", "top_right", "bottom_right", "bottom_left" }) |corner| {
                const radius = &@field(scaled.details.radius, corner);
                radius.width *= self.device_pixel_ratio;
                radius.height *= self.device_pixel_ratio;
            }
            try border.draw(self, scaled);
        },
    };
}

fn scaleRect(self: *const Canvas, rect: Rect) Rect {
    return .{
        .x = rect.x * self.device_pixel_ratio,
        .y = rect.y * self.device_pixel_ratio,
        .width = rect.width * self.device_pixel_ratio,
        .height = rect.height * self.device_pixel_ratio,
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

    // Opaque rectangles on pixel boundaries need no blending.
    if (rgba[3] == 1 and
        left == @floor(left) and
        top == @floor(top) and
        right == @floor(right) and
        bottom == @floor(bottom))
    {
        const x0: usize = @intFromFloat(left);
        const y0: usize = @intFromFloat(top);
        const x1: usize = @intFromFloat(right);
        const y1: usize = @intFromFloat(bottom);
        const rgb: Pixel = .{
            @intFromFloat(@round(rgba[0] * 255)),
            @intFromFloat(@round(rgba[1] * 255)),
            @intFromFloat(@round(rgba[2] * 255)),
        };
        for (y0..y1) |y| @memset(self.pixels[y * self.width + x0 .. y * self.width + x1], rgb);
        return;
    }
    self.blendRect(left, top, right, bottom, rgba);
}

/// Rasterize fractional rectangle coverage before compositing each pixel.
fn blendRect(self: *Canvas, left: f64, top: f64, right: f64, bottom: f64, rgba: [4]f64) void {
    const x0: usize = @intFromFloat(@floor(left));
    const y0: usize = @intFromFloat(@floor(top));
    const x1: usize = @intFromFloat(@ceil(right));
    const y1: usize = @intFromFloat(@ceil(bottom));
    for (y0..y1) |y| {
        const py: f64 = @floatFromInt(y);
        const coverage_y = @min(bottom, py + 1) - @max(top, py);
        for (x0..x1) |x| {
            const px: f64 = @floatFromInt(x);
            const coverage_x = @min(right, px + 1) - @max(left, px);
            const alpha = rgba[3] * coverage_x * coverage_y;
            const pixel = &self.pixels[y * self.width + x];
            compositing.sourceOver(pixel, .{
                rgba[0] * alpha,
                rgba[1] * alpha,
                rgba[2] * alpha,
                alpha,
            });
        }
    }
}
