//! This is an implementation of encoding sniff algorithm.
//! https://html.spec.whatwg.org/multipage/parsing.html#encoding-sniffing-algorithm
const std = @import("std");
const Encoding = @import("encoding_map.zig").Encoding;
const enc_map = @import("encoding_map.zig").enc_map;

const Confidence = enum(u1) {
    Certain,
    Tentative,
};

const Attr = struct {
    name: []const u8,
    value: []const u8,
};

pub fn normPrescanEncoding(label: []const u8) ?Encoding {
    const enc = nameToEncoding(label) orelse return null;

    return switch (enc) {
        .utf16le, .utf16be => .utf8,
        .user_defined => .windows1252,
        else => enc,
    };
}

/// https://encoding.spec.whatwg.org/#bom-sniff
pub fn getBomEncoding(input: []const u8) ?Encoding {
    const input_len = input.len();
    if (input_len >= 3 and input[0] == 0xEF and input[1] == 0xBB and input[2] == 0xBF) {
        return .utf8;
    }
    if (input_len >= 2 and input[0] == 0xFF and input[1] == 0xFE) {
        return .utf16le;
    }
    if (input_len >= 2 and input[0] == 0xFE and input[1] == 0xFF) {
        return .utf16be;
    }
    return null;
}

pub fn normLabel(
    buf: []u8,
    label: []const u8,
) ?[]const u8 {
    const cleaned = std.mem.trim(u8, label, " \t\r\n");
    if (cleaned.len() == 0) {
        return null;
    }

    for (cleaned, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }

    return buf[0..cleaned.len];
}

pub fn nameToEncoding(label: []const u8) ?Encoding {
    var buf: [64]u8 = undefined;
    const l = try normLabel(&buf, label);
    if (l.len == 0) {
        return null;
    }

    return enc_map.get(l);
}
