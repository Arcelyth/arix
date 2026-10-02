const std = @import("std");
const TokenStream = @import("../syntax/TokenStream.zig");
const Token = @import("../syntax/token.zig").Token;
const String = @import("../String.zig");
const names = @import("names.zig");
const ascii = @import("../../utils/ascii.zig");
const color = @import("../values/specified/color.zig");
const ComponentStream = @import("../syntax/ComponentValueStream.zig");
pub const Color = color.Color;
pub const Space = color.Space;
pub const Absolute = color.Absolute;
pub const DeviceCmyk = color.DeviceCmyk;
pub const Custom = color.Custom;
pub const LightDark = color.LightDark;

pub const ParseError = std.mem.Allocator.Error || error{NestingLimit};

pub fn parse(input: *TokenStream) ParseError!?Color {
    input.discardWhitespace();
    return switch (input.consume()) {
        .hash => |hash| parseHexColor(hash.value),
        .ident => |name| parseKeyword(name),

        .function => |name| blk: {
            input.index -= 1;
            var args = try input.block();
            break :blk try parseFunction(name, &args);
        },
        else => null,
    };
}

pub fn parseComponent(input: *ComponentStream) ?Color {
    input.discardWhitespace();
    const value = input.consume() orelse return null;
    return switch (value.*) {
        .preserved_token => |tk| switch (tk) {
            .hash => |hash| parseHexColor(hash.value),
            .ident => |name| parseKeyword(name),
            else => null,
        },
        .function => |function| blk: {
            var args = ComponentStream.init(function.value);
            if (function.name.eqlAscii("color")) {
                args.discardWhitespace();
                const name = args.consumeIdent() orelse break :blk null;
                if (name.startsWith("--")) @panic("TODO: custom-profile color property values");
                break :blk .{ .absolute = parsePredefined(ComponentStream, &args, name) orelse break :blk null };
            }
            if (function.name.eqlAscii("light-dark") or function.name.eqlAscii("device-cmyk"))
                @panic("TODO: light-dark and device-cmyk color property values");
            if (function.name.eqlAscii("var")) @panic("TODO: CSS custom property substitution");
            break :blk .{ .absolute = parseAbsoluteFunction(ComponentStream, function.name, &args) orelse break :blk null };
        },
        .simple_block => null,
    };
}

fn parseHexColor(value: String) ?Color {
    const rgba = parseHex(value) orelse return null;
    return .{ .absolute = .{
        .space = .srgb,
        .channels = .{ @as(f64, @floatFromInt(rgba[0])) / 255, @as(f64, @floatFromInt(rgba[1])) / 255, @as(f64, @floatFromInt(rgba[2])) / 255 },
        .alpha = @as(f64, @floatFromInt(rgba[3])) / 255,
    } };
}

// https://www.w3.org/TR/css-color-4/#color-keywords
fn parseKeyword(name: String) ?Color {
    if (name.eqlAscii("currentcolor")) return .current_color;
    if (name.eqlAscii("transparent"))
        return .{ .absolute = .{ .space = .srgb, .channels = .{ 0, 0, 0 }, .alpha = 0 } };

    var lower: [32]u8 = undefined;
    const key = name.toAsciiLower(&lower) orelse return null;
    if (names.colors.get(key)) |rgb| return .{ .absolute = .{ .space = .srgb, .channels = .{
        @as(f64, @floatFromInt(rgb >> 16)) / 255,
        @as(f64, @floatFromInt((rgb >> 8) & 255)) / 255,
        @as(f64, @floatFromInt(rgb & 255)) / 255,
    } } };
    if (names.system_colors.getIndex(key)) |index| return .{ .system = index };
    return null;
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

fn parseFunction(name: String, args: *TokenStream) ParseError!?Color {
    if (name.eqlAscii("color")) return parseColorFunction(args);
    if (name.eqlAscii("light-dark")) return parseLightDark(args);
    if (name.eqlAscii("device-cmyk"))
        return .{ .device_cmyk = parseDeviceCmyk(args) orelse return null };

    return .{ .absolute = parseAbsoluteFunction(TokenStream, name, args) orelse return null };
}

// Compile-time specialization keeps the two concrete streams separate; there
// is no allocation or runtime dispatch in the shared numeric grammar.
fn parseAbsoluteFunction(comptime Input: type, name: String, args: *Input) ?Absolute {
    return if (name.eqlAscii("rgb") or name.eqlAscii("rgba"))
        parseRgb(Input, args)
    else if (name.eqlAscii("hsl") or name.eqlAscii("hsla"))
        parseHsl(Input, args)
    else if (name.eqlAscii("hwb"))
        parseHwb(Input, args)
    else if (name.eqlAscii("lab"))
        parseLab(Input, args, .lab)
    else if (name.eqlAscii("oklab"))
        parseLab(Input, args, .oklab)
    else if (name.eqlAscii("lch"))
        parseLch(Input, args, .lch)
    else if (name.eqlAscii("oklch"))
        parseLch(Input, args, .oklch)
    else
        null;
}

fn parseRgb(comptime Input: type, args: *Input) ?Absolute {
    args.discardWhitespace();
    const first = consumeColorToken(Input, args);
    const index = args.index;
    args.discardWhitespace();
    return switch (peekColorToken(Input, args)) {
        .comma => parseLegacyRgb(Input, args, first),
        else => if (args.index != index) parseModernRgb(Input, args, first) else null,
    };
}

fn parseLegacyRgb(comptime Input: type, args: *Input, first: Token) ?Absolute {
    const red = rgbChannel(first) orelse return null;

    if (consumeColorToken(Input, args) != .comma) return null;
    args.discardWhitespace();
    const second = consumeColorToken(Input, args);
    if (std.meta.activeTag(second) != std.meta.activeTag(first)) return null;
    const green = rgbChannel(second) orelse return null;

    args.discardWhitespace();
    if (consumeColorToken(Input, args) != .comma) return null;
    args.discardWhitespace();
    const third = consumeColorToken(Input, args);
    if (std.meta.activeTag(third) != std.meta.activeTag(first)) return null;
    const blue = rgbChannel(third) orelse return null;

    return finish(Input, args, .{ .space = .srgb, .channels = .{ red, green, blue } }, true);
}

fn parseModernRgb(comptime Input: type, args: *Input, first: Token) ?Absolute {
    const red: ?f64 = if (isNone(first)) null else rgbChannel(first) orelse return null;
    const second = consumeColorToken(Input, args);
    const green: ?f64 = if (isNone(second)) null else rgbChannel(second) orelse return null;

    const index = args.index;
    args.discardWhitespace();
    if (args.index == index) return null;
    const third = consumeColorToken(Input, args);
    const blue: ?f64 = if (isNone(third)) null else rgbChannel(third) orelse return null;

    return finish(Input, args, .{ .space = .srgb, .channels = .{ red, green, blue } }, false);
}

// Shared numeric conversion and parse-time clamping for both RGB syntaxes.
fn rgbChannel(tk: Token) ?f64 {
    const value = number(tk, 1) orelse return null;
    return std.math.clamp(value / @as(f64, if (tk == .percentage) 100 else 255), 0, 1);
}

// https://drafts.csswg.org/css-color-4/#the-hsl-notation
fn parseHsl(comptime Input: type, args: *Input) ?Absolute {
    args.discardWhitespace();
    const first = consumeColorToken(Input, args);
    args.discardWhitespace();
    return switch (peekColorToken(Input, args)) {
        .comma => parseLegacyHsl(Input, args, first),
        else => parseModernHsl(Input, args, first),
    };
}

// https://drafts.csswg.org/css-color-4/#legacy-hsl-syntax
fn parseLegacyHsl(comptime Input: type, args: *Input, first: Token) ?Absolute {
    const hue = parseHue(first) orelse return null;

    if (consumeColorToken(Input, args) != .comma) return null;
    args.discardWhitespace();
    const saturation = switch (consumeColorToken(Input, args)) {
        .percentage => |p| p.value,
        else => return null,
    };

    args.discardWhitespace();
    if (consumeColorToken(Input, args) != .comma) return null;
    args.discardWhitespace();
    const lightness = switch (consumeColorToken(Input, args)) {
        .percentage => |p| p.value,
        else => return null,
    };
    if (!std.math.isFinite(saturation) or !std.math.isFinite(lightness)) return null;

    return finish(Input, args, .{
        .space = .hsl,
        .channels = .{ hue, @max(0, saturation), lightness },
    }, true);
}

// https://drafts.csswg.org/css-color-4/#modern-hsl-syntax
fn parseModernHsl(comptime Input: type, args: *Input, first: Token) ?Absolute {
    const hue: ?f64 = if (isNone(first)) null else parseHue(first) orelse return null;
    const second = consumeColorToken(Input, args);
    const saturation: ?f64 = if (isNone(second)) null else @max(0, number(second, 1) orelse return null);

    args.discardWhitespace();
    const third = consumeColorToken(Input, args);
    const lightness: ?f64 = if (isNone(third)) null else number(third, 1) orelse return null;

    return finish(Input, args, .{
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
fn parseHwb(comptime Input: type, args: *Input) ?Absolute {
    args.discardWhitespace();
    const first = consumeColorToken(Input, args);
    const hue: ?f64 = if (isNone(first)) null else parseHue(first) orelse return null;

    args.discardWhitespace();
    const second = consumeColorToken(Input, args);
    const whiteness: ?f64 = if (isNone(second)) null else number(second, 1) orelse return null;

    args.discardWhitespace();
    const third = consumeColorToken(Input, args);
    const blackness: ?f64 = if (isNone(third)) null else number(third, 1) orelse return null;

    // Preserve W and B here; achromatic normalization belongs to conversion to sRGB.
    return finish(Input, args, .{
        .space = .hwb,
        .channels = .{ hue, whiteness, blackness },
    }, false);
}

// https://drafts.csswg.org/css-color-4/#funcdef-lab
// https://drafts.csswg.org/css-color-4/#funcdef-oklab
fn parseLab(comptime Input: type, args: *Input, comptime space: Space) ?Absolute {
    const max_lightness: f64 = if (space == .lab) 100 else 1;
    const axis_scale: f64 = if (space == .lab) 1.25 else 0.004;

    args.discardWhitespace();
    const first = consumeColorToken(Input, args);
    const lightness: ?f64 = if (isNone(first)) null else std.math.clamp(number(first, max_lightness / 100) orelse return null, 0, max_lightness);

    args.discardWhitespace();
    const second = consumeColorToken(Input, args);
    const a: ?f64 = if (isNone(second)) null else number(second, axis_scale) orelse return null;

    args.discardWhitespace();
    const third = consumeColorToken(Input, args);
    const b: ?f64 = if (isNone(third)) null else number(third, axis_scale) orelse return null;

    return finish(Input, args, .{
        .space = space,
        .channels = .{ lightness, a, b },
    }, false);
}

// https://drafts.csswg.org/css-color-4/#funcdef-lch
// https://drafts.csswg.org/css-color-4/#funcdef-oklch
fn parseLch(comptime Input: type, args: *Input, comptime space: Space) ?Absolute {
    const max_lightness: f64 = if (space == .lch) 100 else 1;
    const chroma_scale: f64 = if (space == .lch) 1.5 else 0.004;

    args.discardWhitespace();
    const first = consumeColorToken(Input, args);
    const lightness: ?f64 = if (isNone(first)) null else std.math.clamp(number(first, max_lightness / 100) orelse return null, 0, max_lightness);

    args.discardWhitespace();
    const second = consumeColorToken(Input, args);
    const chroma: ?f64 = if (isNone(second)) null else @max(0, number(second, chroma_scale) orelse return null);

    args.discardWhitespace();
    const third = consumeColorToken(Input, args);
    const hue: ?f64 = if (isNone(third)) null else parseHue(third) orelse return null;

    return finish(Input, args, .{
        .space = space,
        .channels = .{ lightness, chroma, hue },
    }, false);
}

// https://drafts.csswg.org/css-color-4/#predefined
fn parsePredefined(comptime Input: type, args: *Input, name: String) ?Absolute {
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
    const first = consumeColorToken(Input, args);
    const x: ?f64 = if (isNone(first)) null else number(first, 0.01) orelse return null;

    args.discardWhitespace();
    const second = consumeColorToken(Input, args);
    const y: ?f64 = if (isNone(second)) null else number(second, 0.01) orelse return null;

    args.discardWhitespace();
    const third = consumeColorToken(Input, args);
    const z: ?f64 = if (isNone(third)) null else number(third, 0.01) orelse return null;

    return finish(Input, args, .{
        .space = space,
        .channels = .{ x, y, z },
    }, false);
}

// https://drafts.csswg.org/css-color-5/#color-function
fn parseColorFunction(args: *TokenStream) ParseError!?Color {
    args.discardWhitespace();
    const name = switch (args.consume()) {
        .ident => |value| value,
        else => return null,
    };
    if (name.startsWith("--")) return parseCustom(args, name);
    return .{ .absolute = parsePredefined(TokenStream, args, name) orelse return null };
}

// https://drafts.csswg.org/css-color-5/#device-cmyk
fn parseDeviceCmyk(args: *TokenStream) ?DeviceCmyk {
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
fn parseLegacyDeviceCmyk(args: *TokenStream, first: Token) ?DeviceCmyk {
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
fn parseModernDeviceCmyk(args: *TokenStream, first: Token) ?DeviceCmyk {
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
    return if (finishAlpha(TokenStream, args, &value.alpha, false)) value else null;
}

// https://drafts.csswg.org/css-color-5/#typedef-custom-params
fn parseCustom(args: *TokenStream, name: String) ParseError!?Color {
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
    if (!finishAlpha(TokenStream, args, &alpha, false)) return null;
    return .{ .custom = .{
        .name = name,
        .channels = try channels.toOwnedSlice(args.allocator),
        .alpha = alpha,
    } };
}

// https://drafts.csswg.org/css-color-5/#light-dark
fn parseLightDark(args: *TokenStream) ParseError!?Color {
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

fn finish(
    comptime Input: type,
    args: *Input,
    value: Absolute,
    comma: bool,
) ?Absolute {
    var result = value;
    return if (finishAlpha(Input, args, &result.alpha, comma)) result else null;
}

// Shared optional-alpha tail and exhaustion check. Legacy syntax uses a comma
// and forbids missing alpha; modern syntax uses '/' and permits none.
fn finishAlpha(
    comptime Input: type,
    args: *Input,
    alpha: *?f64,
    comma: bool,
) bool {
    args.discardWhitespace();
    if (comma and peekColorToken(Input, args) == .comma) {
        _ = consumeColorToken(Input, args);
        alpha.* = parseAlpha(Input, args) orelse return false;
    } else if (!comma and peekColorToken(Input, args) == .delim and peekColorToken(Input, args).delim == '/') {
        _ = consumeColorToken(Input, args);
        args.discardWhitespace();
        if (isNone(peekColorToken(Input, args))) {
            _ = consumeColorToken(Input, args);
            alpha.* = null;
        } else alpha.* = parseAlpha(Input, args) orelse return false;
    }
    args.discardWhitespace();
    return args.empty();
}

// Numeric/percentage alpha only; the caller handles the none keyword.
fn parseAlpha(comptime Input: type, args: *Input) ?f64 {
    args.discardWhitespace();
    const value = number(consumeColorToken(Input, args), 0.01) orelse return null;
    return std.math.clamp(value, 0, 1);
}

fn peekColorToken(comptime Input: type, args: *const Input) Token {
    if (Input == TokenStream) return args.peek();
    const value = args.peek() orelse return .eof;
    if (value.* == .function) @panic("TODO: math and substitution in color coordinates");
    if (value.* == .simple_block) return switch (value.simple_block.associated_token) {
        .left_paren => .left_paren,
        .left_bracket => .left_bracket,
        .left_brace => .left_brace,
    };
    const tk = &value.preserved_token;
    return switch (tk.*) {
        .hash => |hash| .{
            .hash = .{
                .value = hash.value,
                .type_flag = hash.type_flag,
            },
        },
        .number => |n| .{
            .number = .{
                .value = n.value,
                .sign = n.sign,
                .type_flag = n.type_flag,
            },
        },
        .percentage => |p| .{
            .percentage = .{
                .value = p.value,
                .sign = p.sign,
            },
        },
        .dimension => |d| .{
            .dimension = .{
                .value = d.value,
                .sign = d.sign,
                .type_flag = d.type_flag,
                .unit = d.unit,
            },
        },
        .unicode_range => |range| .{
            .unicode_range = .{
                .start = range.start,
                .end = range.end,
            },
        },
        inline else => |payload, tag| @unionInit(Token, @tagName(tag), payload),
    };
}

fn consumeColorToken(comptime Input: type, args: *Input) Token {
    if (Input == TokenStream) return args.consume();
    const tk = peekColorToken(Input, args);
    args.advance();
    return tk;
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
