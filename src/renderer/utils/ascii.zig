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
