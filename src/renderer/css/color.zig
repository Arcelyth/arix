const std = @import("std");
const Stream = @import("TokenStream.zig");
const Token = @import("token.zig").Token;
const String = @import("String.zig");
const names = @import("color_names.zig");
const ascii = @import("../utils/ascii.zig");

pub const Space = enum {
    srgb,
    srgb_linear,
    display_p3,
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
    space: Space = .srgb,
    channels: [3]?f64,
    alpha: ?f64 = 1,
};

pub const Color = union(enum) {
    absolute: Absolute,
    current_color,
    /// Index into the static system color table; not a resolved platform color.
    system: usize,
};

pub fn parse(input: *Stream) error{NestingLimit}!?Color {
    input.discardWhitespace();
    return switch (input.take()) {
        .hash => |hash| if (parseHex(hash.value)) |rgba| .{ .absolute = .{
            .channels = .{ @as(f64, @floatFromInt(rgba[0])) / 255, @as(f64, @floatFromInt(rgba[1])) / 255, @as(f64, @floatFromInt(rgba[2])) / 255 },
            .alpha = @as(f64, @floatFromInt(rgba[3])) / 255,
        } } else null,
        .ident => {},
        .function => {},
        else => null,
    };
}

// https://drafts.csswg.org/css-color-4/#hex-notation
pub fn parseHex(value: String) ?[4]u8 {
    const len = value.len();
    if (len != 3 and len != 4 and len != 6 and len != 8) return null;
    var rgba: [4]u8 = .{ 0, 0, 0, 255 };
    const short = len < 5;
    for (0..if (short) len else len / 2) |i| {
        const first = value.codePoint(if (short) i else i * 2) orelse return null;
        const second = if (short) first else value.codePoint(i * 2 + 1) orelse return null;
        if (!ascii.isAsciiHexDigit(first) or !ascii.isAsciiHexDigit(second)) return null;
        rgba[i] = @as(u8, ascii.toHexDigit(u21, first)) * 16 + ascii.toHexDigit(u21, second);
    }
    return rgba;
}

