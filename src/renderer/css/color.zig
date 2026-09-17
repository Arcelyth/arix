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
    space: Space,
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
    return switch (input.consume()) {
        .hash => |hash| if (parseHex(hash.value)) |rgba| .{ .absolute = .{
            .space = .srgb,
            .channels = .{ @as(f64, @floatFromInt(rgba[0])) / 255, @as(f64, @floatFromInt(rgba[1])) / 255, @as(f64, @floatFromInt(rgba[2])) / 255 },
            .alpha = @as(f64, @floatFromInt(rgba[3])) / 255,
        } } else null,

        .ident => |name| blk: {
            if (name.eqlAscii("currentcolor"))
                break :blk .current_color;
            if (name.eqlAscii("transparent"))
                break :blk .{ .absolute = .{ .space = .srgb, .channels = .{ 0, 0, 0 }, .alpha = 0 } };

            var lower: [32]u8 = undefined;
            const key = name.toAsciiLower(&lower) orelse break :blk null;

            if (names.colors.get(key)) |rgb| break :blk .{ .absolute = .{ .space = .srgb, .channels = .{
                @as(f64, @floatFromInt(rgb >> 16)) / 255,
                @as(f64, @floatFromInt((rgb >> 8) & 255)) / 255,
                @as(f64, @floatFromInt(rgb & 255)) / 255,
            } } };
            if (names.system_colors.getIndex(key)) |index| break :blk .{ .system = index };
            break :blk null;
        },

        .function => |name| blk: {
            input.index -= 1;
            var args = try input.block();
            break :blk if (parseFunction(name, &args)) |value| .{ .absolute = value } else null;
        },
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

fn parseFunction(name: String, args: *Stream) ?Absolute {
    if (name.eqlAscii("rgb") or name.eqlAscii("rgba")) return parseRgb(args);
    if (name.eqlAscii("hsl") or name.eqlAscii("hsla")) return parseHsl(args);
    if (name.eqlAscii("hwb")) return parseHwb(args);
    if (name.eqlAscii("lab")) return parseLab(args, .lab);
    if (name.eqlAscii("oklab")) return parseLab(args, .oklab);
    if (name.eqlAscii("lch")) return parseLch(args, .lch);
    if (name.eqlAscii("oklch")) return parseLch(args, .oklch);
    if (name.eqlAscii("color")) return parsePredefined(args);
    return null;
}

fn parseRgb(args: *Stream) ?Absolute {
    args.discardWhitespace();
    const first = args.consume();
    const index = args.index;
    args.discardWhitespace();
    return switch (args.peek()) {
        .comma => parseLegacyRgb(args, first),
        else => if (args.index != index) parseModernRgb(args, first) else null,
    };
}

fn parseLegacyRgb(args: *Stream, first: Token) ?Absolute {
    const red = rgbChannel(first) orelse return null;

    if (args.consume() != .comma) return null;
    args.discardWhitespace();
    const second = args.consume();
    if (std.meta.activeTag(second) != std.meta.activeTag(first)) return null;
    const green = rgbChannel(second) orelse return null;

    args.discardWhitespace();
    if (args.consume() != .comma) return null;
    args.discardWhitespace();
    const third = args.consume();
    if (std.meta.activeTag(third) != std.meta.activeTag(first)) return null;
    const blue = rgbChannel(third) orelse return null;

    return finish(args, .{ .space = .srgb, .channels = .{ red, green, blue } }, true);
}

fn parseModernRgb(args: *Stream, first: Token) ?Absolute {
    const red: ?f64 = if (isNone(first)) null else rgbChannel(first) orelse return null;
    const second = args.consume();
    const green: ?f64 = if (isNone(second)) null else rgbChannel(second) orelse return null;

    const index = args.index;
    args.discardWhitespace();
    if (args.index == index) return null;
    const third = args.consume();
    const blue: ?f64 = if (isNone(third)) null else rgbChannel(third) orelse return null;

    return finish(args, .{ .space = .srgb, .channels = .{ red, green, blue } }, false);
}

// Shared numeric conversion and parse-time clamping for both RGB syntaxes.
fn rgbChannel(tk: Token) ?f64 {
    const value = number(tk, 1) orelse return null;
    return std.math.clamp(value / @as(f64, if (tk == .percentage) 100 else 255), 0, 1);
}

// https://drafts.csswg.org/css-color-4/#the-hsl-notation
fn parseHsl(args: *Stream) ?Absolute {
    args.discardWhitespace();
    const first = args.consume();
    args.discardWhitespace();
    return switch (args.peek()) {
        .comma => parseLegacyHsl(args, first),
        else => parseModernHsl(args, first),
    };
}

// https://drafts.csswg.org/css-color-4/#legacy-hsl-syntax
fn parseLegacyHsl(args: *Stream, first: Token) ?Absolute {
    const hue = parseHue(first) orelse return null;

    if (args.consume() != .comma) return null;
    args.discardWhitespace();
    const saturation = switch (args.consume()) {
        .percentage => |p| p.value,
        else => return null,
    };

    args.discardWhitespace();
    if (args.consume() != .comma) return null;
    args.discardWhitespace();
    const lightness = switch (args.consume()) {
        .percentage => |p| p.value,
        else => return null,
    };
    if (!std.math.isFinite(saturation) or !std.math.isFinite(lightness)) return null;

    return finish(args, .{
        .space = .hsl,
        .channels = .{ hue, @max(0, saturation), lightness },
    }, true);
}

// https://drafts.csswg.org/css-color-4/#modern-hsl-syntax
fn parseModernHsl(args: *Stream, first: Token) ?Absolute {
    const hue: ?f64 = if (isNone(first)) null else parseHue(first) orelse return null;
    const second = args.consume();
    const saturation: ?f64 = if (isNone(second)) null else @max(0, number(second, 1) orelse return null);

    args.discardWhitespace();
    const third = args.consume();
    const lightness: ?f64 = if (isNone(third)) null else number(third, 1) orelse return null;

    return finish(args, .{
        .space = .hsl,
        .channels = .{ hue, saturation, lightness },
    }, false);
}

// https://drafts.csswg.org/css-color-4/#typedef-hue
fn parseHue(tk: Token) ?f64 {
    const degrees = switch (tk) {
        .number => |n| n.value,
        // https://drafts.csswg.org/css-values-4/#angle-value
        .dimension => |d| blk: {
            if (!std.math.isFinite(d.value)) return null;
            if (d.unit.eqlAscii("deg")) break :blk d.value;
            if (d.unit.eqlAscii("grad")) break :blk @mod(d.value, 400) * 0.9;
            if (d.unit.eqlAscii("rad")) break :blk @mod(d.value, 2 * std.math.pi) * (180.0 / std.math.pi);
            if (d.unit.eqlAscii("turn")) break :blk @mod(d.value, 1) * 360;
            return null;
        },
        else => return null,
    };
    if (!std.math.isFinite(degrees)) return null;
    return @mod(degrees, 360);
}

fn parseHwb(args: *Stream) ?Absolute {
    _ = args;
    return null;
}

fn parseLab(args: *Stream, comptime space: Space) ?Absolute {
    _ = args;
    _ = space;
    return null;
}

fn parseLch(args: *Stream, comptime space: Space) ?Absolute {
    _ = args;
    _ = space;
    return null;
}

fn parsePredefined(args: *Stream) ?Absolute {
    _ = args;
    return null;
}

// Helper for literal coordinates: scale percentages, leave
// numbers unchanged, and reject non-finite input.
fn number(tk: Token, percentage_scale: f64) ?f64 {
    const value = switch (tk) {
        .number => |n| n.value,
        .percentage => |p| p.value * percentage_scale,
        else => return null,
    };
    return if (std.math.isFinite(value)) value else null;
}

inline fn isNone(tk: Token) bool {
    return tk == .ident and tk.ident.eqlAscii("none");
}

// Shared optional-alpha tail and exhaustion check. Legacy syntax uses a comma
// and forbids missing alpha; modern syntax uses '/' and permits none.
fn finish(args: *Stream, value: Absolute, comma: bool) ?Absolute {
    var result = value;
    args.discardWhitespace();
    if (comma and args.peek() == .comma) {
        _ = args.consume();
        result.alpha = parseAlpha(args) orelse return null;
    } else if (!comma and args.peek() == .delim and args.peek().delim == '/') {
        _ = args.consume();
        args.discardWhitespace();
        if (isNone(args.peek())) {
            _ = args.consume();
            result.alpha = null;
        } else result.alpha = parseAlpha(args) orelse return null;
    }
    args.discardWhitespace();
    return if (args.empty()) result else null;
}

// Numeric/percentage alpha only; the caller handles the none keyword.
fn parseAlpha(args: *Stream) ?f64 {
    args.discardWhitespace();
    const value = number(args.consume(), 0.01) orelse return null;
    return std.math.clamp(value, 0, 1);
}
