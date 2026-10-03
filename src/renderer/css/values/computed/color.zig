const color = @import("../../color/parse.zig");
const SpecifiedColor = color.Color;
const Context = @import("Context.zig");
const std = @import("std");

/// https://www.w3.org/TR/css-color-4/#resolving-color-values
pub const Color = union(enum) {
    absolute: color.Absolute,
    current_color,

    pub const transparent: Color = .{
        .absolute = .{
            .space = .srgb,
            .channels = .{ 0, 0, 0 },
            .alpha = 0,
        },
    };

    pub fn fromSpecified(value: SpecifiedColor, context: *const Context) Color {
        _ = context;
        return switch (value) {
            .absolute => |absolute| blk: {
                var result = absolute;
                const rgb = switch (absolute.space) {
                    .hsl => color.hslToRgb(
                        absolute.channels[0] orelse 0,
                        std.math.clamp(absolute.channels[1] orelse 0, 0, 100),
                        std.math.clamp(absolute.channels[2] orelse 0, 0, 100),
                    ),
                    .hwb => color.hwbToRgb(
                        absolute.channels[0] orelse 0,
                        std.math.clamp(absolute.channels[1] orelse 0, 0, 100),
                        std.math.clamp(absolute.channels[2] orelse 0, 0, 100),
                    ),
                    else => break :blk .{ .absolute = result },
                };
                result.space = .srgb;
                result.channels = .{ rgb[0], rgb[1], rgb[2] };
                break :blk .{ .absolute = result };
            },
            .current_color => .current_color,
            .system => @panic("TODO: platform system color resolution"),
            .device_cmyk, .custom, .light_dark => @panic("TODO: device, custom-profile and light-dark color computation"),
        };
    }
};
