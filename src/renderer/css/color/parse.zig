const std = @import("std");
const Stream = @import("../syntax/TokenStream.zig");
const Token = @import("../syntax/token.zig").Token;
const String = @import("../String.zig");
const names = @import("names.zig");
const ascii = @import("../../utils/ascii.zig");

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

pub const LightDark = struct { light: Color, dark: Color };

pub const ParseError = std.mem.Allocator.Error || error{NestingLimit};

pub fn parse(input: *Stream) ParseError!?Color {
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
            break :blk try parseFunction(name, &args);
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

fn parseFunction(name: String, args: *Stream) ParseError!?Color {
    if (name.eqlAscii("color")) return parseColorFunction(args);
    if (name.eqlAscii("light-dark")) return parseLightDark(args);
    if (name.eqlAscii("device-cmyk"))
        return .{ .device_cmyk = parseDeviceCmyk(args) orelse return null };

    const value = if (name.eqlAscii("rgb") or name.eqlAscii("rgba"))
        parseRgb(args)
    else if (name.eqlAscii("hsl") or name.eqlAscii("hsla"))
        parseHsl(args)
    else if (name.eqlAscii("hwb"))
        parseHwb(args)
    else if (name.eqlAscii("lab"))
        parseLab(args, .lab)
    else if (name.eqlAscii("oklab"))
        parseLab(args, .oklab)
    else if (name.eqlAscii("lch"))
        parseLch(args, .lch)
    else if (name.eqlAscii("oklch"))
        parseLch(args, .oklch)
    else
        null;
    return .{ .absolute = value orelse return null };
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

// https://drafts.csswg.org/css-color-4/#the-hwb-notation
fn parseHwb(args: *Stream) ?Absolute {
    args.discardWhitespace();
    const first = args.consume();
    const hue: ?f64 = if (isNone(first)) null else parseHue(first) orelse return null;

    args.discardWhitespace();
    const second = args.consume();
    const whiteness: ?f64 = if (isNone(second)) null else number(second, 1) orelse return null;

    args.discardWhitespace();
    const third = args.consume();
    const blackness: ?f64 = if (isNone(third)) null else number(third, 1) orelse return null;

    // Preserve W and B here; achromatic normalization belongs to conversion to sRGB.
    return finish(args, .{
        .space = .hwb,
        .channels = .{ hue, whiteness, blackness },
    }, false);
}

// https://drafts.csswg.org/css-color-4/#funcdef-lab
// https://drafts.csswg.org/css-color-4/#funcdef-oklab
fn parseLab(args: *Stream, comptime space: Space) ?Absolute {
    const max_lightness: f64 = if (space == .lab) 100 else 1;
    const axis_scale: f64 = if (space == .lab) 1.25 else 0.004;

    args.discardWhitespace();
    const first = args.consume();
    const lightness: ?f64 = if (isNone(first)) null else std.math.clamp(number(first, max_lightness / 100) orelse return null, 0, max_lightness);

    args.discardWhitespace();
    const second = args.consume();
    const a: ?f64 = if (isNone(second)) null else number(second, axis_scale) orelse return null;

    args.discardWhitespace();
    const third = args.consume();
    const b: ?f64 = if (isNone(third)) null else number(third, axis_scale) orelse return null;

    return finish(args, .{
        .space = space,
        .channels = .{ lightness, a, b },
    }, false);
}

// https://drafts.csswg.org/css-color-4/#funcdef-lch
// https://drafts.csswg.org/css-color-4/#funcdef-oklch
fn parseLch(args: *Stream, comptime space: Space) ?Absolute {
    const max_lightness: f64 = if (space == .lch) 100 else 1;
    const chroma_scale: f64 = if (space == .lch) 1.5 else 0.004;

    args.discardWhitespace();
    const first = args.consume();
    const lightness: ?f64 = if (isNone(first)) null else std.math.clamp(number(first, max_lightness / 100) orelse return null, 0, max_lightness);

    args.discardWhitespace();
    const second = args.consume();
    const chroma: ?f64 = if (isNone(second)) null else @max(0, number(second, chroma_scale) orelse return null);

    args.discardWhitespace();
    const third = args.consume();
    const hue: ?f64 = if (isNone(third)) null else parseHue(third) orelse return null;

    return finish(args, .{
        .space = space,
        .channels = .{ lightness, chroma, hue },
    }, false);
}

// https://drafts.csswg.org/css-color-4/#predefined
fn parsePredefined(args: *Stream, name: String) ?Absolute {
    const space: Space = blk: {
        if (name.eqlAscii("srgb")) break :blk .srgb;
        if (name.eqlAscii("srgb-linear")) break :blk .srgb_linear;
        if (name.eqlAscii("display-p3")) break :blk .display_p3;
        if (name.eqlAscii("display-p3-linear")) break :blk .display_p3_linear;
        if (name.eqlAscii("a98-rgb")) break :blk .a98_rgb;
        if (name.eqlAscii("prophoto-rgb")) break :blk .prophoto_rgb;
        if (name.eqlAscii("rec2020")) break :blk .rec2020;
        if (name.eqlAscii("xyz-d50")) break :blk .xyz_d50;
        if (name.eqlAscii("xyz-d65") or name.eqlAscii("xyz")) break :blk .xyz_d65;
        return null;
    };

    args.discardWhitespace();
    const first = args.consume();
    const x: ?f64 = if (isNone(first)) null else number(first, 0.01) orelse return null;

    args.discardWhitespace();
    const second = args.consume();
    const y: ?f64 = if (isNone(second)) null else number(second, 0.01) orelse return null;

    args.discardWhitespace();
    const third = args.consume();
    const z: ?f64 = if (isNone(third)) null else number(third, 0.01) orelse return null;

    return finish(args, .{
        .space = space,
        .channels = .{ x, y, z },
    }, false);
}

// https://drafts.csswg.org/css-color-5/#color-function
fn parseColorFunction(args: *Stream) ParseError!?Color {
    args.discardWhitespace();
    const name = switch (args.consume()) {
        .ident => |value| value,
        else => return null,
    };
    if (name.startsWith("--")) return parseCustom(args, name);
    return .{ .absolute = parsePredefined(args, name) orelse return null };
}

// https://drafts.csswg.org/css-color-5/#device-cmyk
fn parseDeviceCmyk(args: *Stream) ?DeviceCmyk {
    args.discardWhitespace();
    const first = args.consume();
    const index = args.index;
    args.discardWhitespace();
    return switch (args.peek()) {
        .comma => parseLegacyDeviceCmyk(args, first),
        else => if (args.index != index) parseModernDeviceCmyk(args, first) else null,
    };
}

// https://drafts.csswg.org/css-color-5/#typedef-legacy-device-cmyk-syntax
fn parseLegacyDeviceCmyk(args: *Stream, first: Token) ?DeviceCmyk {
    if (first != .number) return null;
    var value: DeviceCmyk = .{ .channels = .{ number(first, 1) orelse return null, null, null, null } };
    for (value.channels[1..]) |*channel| {
        if (args.consume() != .comma) return null;
        args.discardWhitespace();
        const tk = args.consume();
        if (tk != .number) return null;
        channel.* = number(tk, 1) orelse return null;
        args.discardWhitespace();
    }
    return if (args.empty()) value else null;
}

// https://drafts.csswg.org/css-color-5/#typedef-modern-device-cmyk-syntax
fn parseModernDeviceCmyk(args: *Stream, first: Token) ?DeviceCmyk {
    var value: DeviceCmyk = .{ .channels = .{ null, null, null, null } };
    if (!isNone(first)) value.channels[0] = number(first, 0.01) orelse return null;
    for (value.channels[1..], 0..) |*channel, i| {
        if (i != 0) {
            const index = args.index;
            args.discardWhitespace();
            if (args.index == index) return null;
        }
        const tk = args.consume();
        channel.* = if (isNone(tk)) null else number(tk, 0.01) orelse return null;
    }
    return if (finishAlpha(args, &value.alpha, false)) value else null;
}

// https://drafts.csswg.org/css-color-5/#typedef-custom-params
fn parseCustom(args: *Stream, name: String) ParseError!?Color {
    var channels: std.ArrayList(?f64) = .empty;
    defer channels.deinit(args.allocator);

    while (true) {
        const index = args.index;
        args.discardWhitespace();
        const tk = args.peek();
        if (tk == .eof or (tk == .delim and tk.delim == '/')) break;
        if (args.index == index) return null;
        _ = args.consume();
        try channels.append(args.allocator, if (isNone(tk)) null else number(tk, 0.01) orelse return null);
    }
    if (channels.items.len == 0) return null;
    var alpha: ?f64 = 1;
    if (!finishAlpha(args, &alpha, false)) return null;
    return .{ .custom = .{
        .name = name,
        .channels = try channels.toOwnedSlice(args.allocator),
        .alpha = alpha,
    } };
}

// https://drafts.csswg.org/css-color-5/#light-dark
fn parseLightDark(args: *Stream) ParseError!?Color {
    var transferred = false;
    const light = try parse(args) orelse return null;
    defer if (!transferred) light.deinit(args.allocator);
    args.discardWhitespace();
    if (args.consume() != .comma) return null;
    const dark = try parse(args) orelse return null;
    defer if (!transferred) dark.deinit(args.allocator);
    args.discardWhitespace();
    if (!args.empty()) return null;

    const pair = try args.allocator.create(LightDark);
    pair.* = .{ .light = light, .dark = dark };
    transferred = true;
    return .{ .light_dark = pair };
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

fn finish(args: *Stream, value: Absolute, comma: bool) ?Absolute {
    var result = value;
    return if (finishAlpha(args, &result.alpha, comma)) result else null;
}

// Shared optional-alpha tail and exhaustion check. Legacy syntax uses a comma
// and forbids missing alpha; modern syntax uses '/' and permits none.
fn finishAlpha(args: *Stream, alpha: *?f64, comma: bool) bool {
    args.discardWhitespace();
    if (comma and args.peek() == .comma) {
        _ = args.consume();
        alpha.* = parseAlpha(args) orelse return false;
    } else if (!comma and args.peek() == .delim and args.peek().delim == '/') {
        _ = args.consume();
        args.discardWhitespace();
        if (isNone(args.peek())) {
            _ = args.consume();
            alpha.* = null;
        } else alpha.* = parseAlpha(args) orelse return false;
    }
    args.discardWhitespace();
    return args.empty();
}

// Numeric/percentage alpha only; the caller handles the none keyword.
fn parseAlpha(args: *Stream) ?f64 {
    args.discardWhitespace();
    const value = number(args.consume(), 0.01) orelse return null;
    return std.math.clamp(value, 0, 1);
}

// https://drafts.csswg.org/css-color-4/#hsl-to-rgb
pub fn hslToRgb(hue: f64, saturation: f64, lightness: f64) [3]f64 {
    const light = lightness / 100;
    const amplitude = saturation / 100 * @min(light, 1 - light);
    var rgb: [3]f64 = .{ 0, 8, 4 };
    for (&rgb) |*channel| {
        const k = @mod(channel.* + hue / 30, 12);
        channel.* = light - amplitude * @max(-1, @min(k - 3, 9 - k, 1));
    }
    return rgb;
}

// https://drafts.csswg.org/css-color-4/#hwb-to-rgb
pub fn hwbToRgb(hue: f64, whiteness: f64, blackness: f64) [3]f64 {
    const white = whiteness / 100;
    const black = blackness / 100;
    if (white + black >= 1) {
        const gray = white / (white + black);
        return .{ gray, gray, gray };
    }
    var rgb = hslToRgb(hue, 100, 50);
    for (&rgb) |*channel| channel.* = channel.* * (1 - white - black) + white;
    return rgb;
}
