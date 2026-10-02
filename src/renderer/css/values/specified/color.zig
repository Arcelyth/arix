const std = @import("std");
const String = @import("../../../css/String.zig");

pub const Space = enum {
    srgb,
    srgb_linear,
    display_p3,
    display_p3_linear,
    a98_rgb,
    prophoto_rgb,
    rec2020,
    xyz_d50,
    xyz_d65,
    hsl,
    hwb,
    lab,
    lch,
    oklab,
    oklch,
};

pub const Absolute = struct {
    space: Space,
    channels: [3]?f64,
    alpha: ?f64 = 1,
};

pub const DeviceCmyk = struct {
    // Specified values: channel clamping belongs to computed-value resolution.
    channels: [4]?f64,
    alpha: ?f64 = 1,
};

pub const Custom = struct {
    name: String,
    channels: []const ?f64,
    alpha: ?f64 = 1,
};

pub const LightDark = struct { light: Color, dark: Color };

pub const Color = union(enum) {
    absolute: Absolute,
    current_color,
    /// Index into the static system color table; not a resolved platform color.
    system: usize,

    device_cmyk: DeviceCmyk,
    custom: Custom,
    light_dark: *const LightDark,

    /// Release storage allocated through the token stream's allocator.
    /// Custom profile names borrow token/source storage, which must outlive Color.
    pub fn deinit(self: Color, allocator: std.mem.Allocator) void {
        switch (self) {
            .custom => |value| allocator.free(value.channels),
            .light_dark => |value| {
                value.light.deinit(allocator);
                value.dark.deinit(allocator);
                allocator.destroy(value);
            },
            else => {},
        }
    }
};
