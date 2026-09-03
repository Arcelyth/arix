const std = @import("std");

pub const maximum_code_point: u21 = 0x10FFFF;

pub inline fn isHtmlSpace(c: u8) bool {
    return switch (c) {
        0x09, 0x0A, 0x0C, 0x0D, 0x20 => true,
        else => false,
    };
}

pub inline fn isUtf16Family(enc: []const u8) bool {
    return std.ascii.eqlIgnoreCase(enc, "UTF-16LE") or std.ascii.eqlIgnoreCase(enc, "UTF-16BE");
}

pub inline fn isAsciiAlpha(c: u21) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

pub inline fn isAsciiUpperAlpha(c: u21) bool {
    return c >= 'A' and c <= 'Z';
}

pub inline fn isAsciiLowerAlpha(c: u21) bool {
    return c >= 'a' and c <= 'z';
}

pub inline fn isAsciiDigit(c: u21) bool {
    return c >= '0' and c <= '9';
}

pub inline fn isAsciiAlphanum(c: u21) bool {
    return isAsciiAlpha(c) or isAsciiDigit(c);
}

pub inline fn isAsciiHexDigit(c: u21) bool {
    return isAsciiDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

// https://infra.spec.whatwg.org/#surrogate
pub inline fn isSurrogate(comptime T: type, c: T) bool {
    return (c >= 0xD800 and c <= 0xDBFF) or (c >= 0xDC00 and c <= 0xDFFF);
}

// https://infra.spec.whatwg.org/#noncharacter
pub inline fn isNoneCharacter(comptime T: type, c: T) bool {
    if (c >= 0xFDD0 and c <= 0xFDEF) return true;
    return c <= 0x10FFFF and (c & 0xFFFE) == 0xFFFE;
}

// https://infra.spec.whatwg.org/#ascii-whitespace
pub inline fn isAsciiWhitespace(comptime T: type, c: T) bool {
    return c == 0x09 or c == 0x0A or c == 0x0C or c == 0x0D or c == 0x20;
}

// https://infra.spec.whatwg.org/#control
pub inline fn isControl(comptime T: type, c: T) bool {
    if (c == 0) return false;
    if (isAsciiWhitespace(T, c)) return false;
    return (c >= 0x0001 and c <= 0x001F) or (c >= 0x007F and c <= 0x009F);
}

pub inline fn isNoncharacter(comptime T: type, ch: T) bool {
    return (ch >= 0xFDD0 and ch <= 0xFDEF) or
        ((ch & 0xFFFE) == 0xFFFE and ch <= 0x10FFFF);
}

pub inline fn isControlCharacter(comptime T: type, ch: T) bool {
    return (ch >= 0x0001 and ch <= 0x0008) or
        ch == 0x000B or
        (ch >= 0x000E and ch <= 0x001F) or
        (ch >= 0x007F and ch <= 0x009F);
}

// https://drafts.csswg.org/css-syntax/#non-ascii-ident-code-point
pub inline fn isNonAsciiIdent(c: u21) bool {
    return c == 0x00B7 or
        (c >= 0x00C0 and c <= 0x00D6) or
        (c >= 0x00D8 and c <= 0x00F6) or
        (c >= 0x00F8 and c <= 0x037D) or
        (c >= 0x037F and c <= 0x1FFF) or
        c == 0x200C or
        c == 0x200D or
        c == 0x203F or
        c == 0x2040 or
        (c >= 0x2070 and c <= 0x218F) or
        (c >= 0x2C00 and c <= 0x2FEF) or
        (c >= 0x3001 and c <= 0xD7FF) or
        (c >= 0xF900 and c <= 0xFDCF) or
        (c >= 0xFDF0 and c <= 0xFFFD) or
        c >= 0x10000;
}

// https://drafts.csswg.org/css-syntax/#ident-start-code-point
pub inline fn isCssIdentStart(c: u21) bool {
    return isAsciiAlpha(c) or isNonAsciiIdent(c) or c == '_';
}

// https://drafts.csswg.org/css-syntax/#ident-code-point
pub inline fn isCssIdent(c: u21) bool {
    return isCssIdentStart(c) or isAsciiDigit(c) or c == '-';
}

pub inline fn isCssIdent_O(cp: ?u21) bool {
    return if (cp) |value| isCssIdent(value) else false;
}

//https://drafts.csswg.org/css-syntax/#non-printable-code-point
pub inline fn isCssNonPrintable(c: u21) bool {
    return c <= 0x0008 or
        c == 0x000B or
        (c >= 0x000E and c <= 0x001F) or
        c == 0x007F;
}

// CR and FF have already been normalized during preprocessing.
// https://drafts.csswg.org/css-syntax/#newline
pub inline fn isCssNewline(c: u21) bool {
    return c == '\n';
}

// https://drafts.csswg.org/css-syntax/#whitespace
pub inline fn isCssWhitespace(c: u21) bool {
    return isCssNewline(c) or c == '\t' or c == ' ';
}

pub inline fn asciiCaseInsensitiveEq(value: []const u21, expected: []const u8) bool {
    if (value.len != expected.len) return false;
    for (value, expected) |cp, byte| {
        if (cp > 0x7f) return false;
        if (std.ascii.toLower(@as(u8, @intCast(cp))) != std.ascii.toLower(byte))
            return false;
    }
    return true;
}

// https://drafts.css-houdini.org/css-typed-om-1/#custom-property-name-string
pub inline fn isCustomPropertyName(comptime T: type, str: []const T) bool {
    return str.len >= 2 and str[0] == '-' and str[1] == '-';
}

pub inline fn toHexDigit(comptime T: type, cp: T) u4 {
    return switch (cp) {
        '0'...'9' => @intCast(cp - '0'),
        'A'...'F' => @intCast(cp - 'A' + 10),
        'a'...'f' => @intCast(cp - 'a' + 10),
        else => unreachable,
    };
}

const testing = std.testing;

test "CSS: code-point definitions" {
    try testing.expect(isAsciiDigit('0'));
    try testing.expect(isAsciiHexDigit('F'));
    try testing.expect(!isAsciiHexDigit('g'));
    try testing.expect(isCssIdentStart('_'));
    try testing.expect(!isCssIdentStart('-'));
    try testing.expect(isCssIdent('-'));
    try testing.expect(isCssWhitespace('\n'));
    try testing.expect(!isCssWhitespace('\r'));
    try testing.expect(isCssNonPrintable(0x007F));
    try testing.expect(!isCssNonPrintable(0x0080));
}

test "CSS: non-ASCII ident boundaries" {
    try testing.expect(isNonAsciiIdent(0x00B7));
    try testing.expect(!isNonAsciiIdent(0x00B8));
    try testing.expect(isNonAsciiIdent(0x00C0));
    try testing.expect(isNonAsciiIdent(0x00D6));
    try testing.expect(!isNonAsciiIdent(0x00D7));
    try testing.expect(isNonAsciiIdent(0x037D));
    try testing.expect(!isNonAsciiIdent(0x037E));
    try testing.expect(isNonAsciiIdent(0x037F));
    try testing.expect(isNonAsciiIdent(0xFFFD));
    try testing.expect(!isNonAsciiIdent(0xFFFE));
    try testing.expect(isNonAsciiIdent(0x10000));
    try testing.expect(isNonAsciiIdent(0x10FFFF));
}
