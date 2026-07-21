const std = @import("std");

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
pub inline fn isSurrogate(c: u21) bool {
    return (c >= 0xD800 and c <= 0xDBFF) or (c >= 0xDC00 and c <= 0xDFFF);
}

// https://infra.spec.whatwg.org/#noncharacter
pub inline fn isNoneCharacter(c: u21) bool {
    if (c >= 0xFDD0 and c <= 0xFDEF) return true;
    return c <= 0x10FFFF and (c & 0xFFFE) == 0xFFFE;
}

// https://infra.spec.whatwg.org/#ascii-whitespace
pub inline fn isAsciiWhitespace(c: u21) bool {
    return c == 0x09 or c == 0x0A or c == 0x0C or c == 0x0D or c == 0x20;
}

// https://infra.spec.whatwg.org/#control
pub inline fn isControl(c: u21) bool {
    if (c == 0) return false;
    if (isAsciiWhitespace(c)) return false;
    return (c >= 0x0001 and c <= 0x001F) or (c >= 0x007F and c <= 0x009F);
}
