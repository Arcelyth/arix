//! https://url.spec.whatwg.org/#percent-encoded-bytes
const std = @import("std");
const ascii = @import("../../utils/ascii.zig");

/// The percent-encode set.
/// https://url.spec.whatwg.org/#percent-encode-set
pub const Set = enum {
    c0_control,
    fragment,
    query,
    special_query,
    path,
    userinfo,
    component,

    /// Checks whether the byte belongs to the chosen percent-encode set.
    /// - true: encode it as %HH.
    /// - false: append it unchanged.
    ///
    /// For example, contains(.userinfo, '@') returns true, so @ becomes %40.
    fn contains(self: Set, byte: u8) bool {
        if (byte <= 0x1f or byte > 0x7e) return true;
        return switch (self) {
            .c0_control => false,
            .fragment => switch (byte) {
                ' ', '"', '<', '>', '`' => true,
                else => false,
            },
            .query => switch (byte) {
                ' ', '"', '#', '<', '>' => true,
                else => false,
            },
            .special_query => contains(.query, byte) or byte == '\'',
            .path => contains(.query, byte) or switch (byte) {
                '?', '^', '`', '{', '}' => true,
                else => false,
            },
            .userinfo => contains(.path, byte) or switch (byte) {
                '/', ':', ';', '=', '@', '[', '\\', ']', '|' => true,
                else => false,
            },
            .component => contains(.userinfo, byte) or switch (byte) {
                '$'...'&', '+', ',' => true,
                else => false,
            },
        };
    }
};

pub fn appendByte(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    byte: u8,
    set: Set,
) !void {
    if (!set.contains(byte)) return output.append(allocator, byte);
    const hex = "0123456789ABCDEF";
    try output.appendSlice(allocator, &.{ '%', hex[byte >> 4], hex[byte & 15] });
}

pub fn append(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    cp: u21,
    set: Set,
) !void {
    var bytes: [4]u8 = undefined;
    const length = try std.unicode.utf8Encode(cp, &bytes);
    for (bytes[0..length]) |byte| try appendByte(allocator, output, byte, set);
}
