/// String type for optimizing.
///
/// Most strings are represented as borrowed slices of the original
/// source buffer, avoiding allocations and copies on the common path.
/// Strings that require decoding are materialized into owned storage.
const String = @This();

const std = @import("std");

pub const Case = enum {
    exact,
    ignore_ascii,
    /// Lowercase only `self` during comparison, leaving the other string intact.
    lower_self,
};

value: union(enum) {
    borrowed: []const u8,
    owned: []const u21,
},

pub inline fn fromSource(bytes: []const u8) String {
    return .{ .value = .{ .borrowed = bytes } };
}

pub inline fn fromDecoded(code_points: []const u21) String {
    return .{ .value = .{ .owned = code_points } };
}

/// Case-sensitive equality, including escaped versus UTF-8 source names.
pub fn eql(self: String, other: String) bool {
    return switch (self.value) {
        .borrowed => |bytes| switch (other.value) {
            .borrowed => |right| std.mem.eql(u8, bytes, right),
            .owned => |right| eqlDecoded(bytes, right),
        },
        .owned => |code_points| switch (other.value) {
            .borrowed => |right| eqlDecoded(right, code_points),
            .owned => |right| std.mem.eql(u21, code_points, right),
        },
    };
}

fn eqlDecoded(bytes: []const u8, code_points: []const u21) bool {
    var iterator = std.unicode.Utf8Iterator{ .bytes = bytes, .i = 0 };
    for (code_points) |cp| {
        if ((iterator.nextCodepoint() orelse return false) != cp) return false;
    }
    return iterator.nextCodepoint() == null;
}

pub fn eqlAscii(self: String, expected: []const u8) bool {
    return switch (self.value) {
        .borrowed => |bytes| std.ascii.eqlIgnoreCase(bytes, expected),
        .owned => |code_points| blk: {
            if (code_points.len != expected.len) break :blk false;
            for (code_points, expected) |cp, byte| {
                if (cp > 0x7f or std.ascii.toLower(@as(u8, @intCast(cp))) != std.ascii.toLower(byte))
                    break :blk false;
            }
            break :blk true;
        },
    };
}

pub fn eqlUtf8WithCase(self: String, bytes: []const u8, mode: Case) bool {
    if (mode == .exact and self.value == .borrowed)
        return std.mem.eql(u8, self.value.borrowed, bytes);
    return (self.prefixLength(bytes, mode) orelse return false) == bytes.len;
}

/// Match this string at the start of `bytes`, returning the number of UTF-8
/// bytes matched, or null on mismatch. An empty string matches zero bytes.
pub fn prefixLength(self: String, bytes: []const u8, mode: Case) ?usize {
    switch (self.value) {
        .borrowed => |expected| {
            if (expected.len > bytes.len) return null;
            if (mode == .exact) return if (std.mem.startsWith(u8, bytes, expected)) expected.len else null;
            for (expected, bytes[0..expected.len]) |left, right| {
                const rhs = if (mode == .ignore_ascii) std.ascii.toLower(right) else right;
                if (std.ascii.toLower(left) != rhs) return null;
            }
            return expected.len;
        },
        .owned => |points| {
            var cursor: usize = 0;
            for (points) |cp| {
                if (cursor == bytes.len) return null;
                const length = std.unicode.utf8ByteSequenceLength(bytes[cursor]) catch return null;
                if (length > bytes.len - cursor) return null;
                const right = std.unicode.utf8Decode(bytes[cursor..][0..length]) catch return null;
                const left = if (mode != .exact and cp <= 0x7F) std.ascii.toLower(@as(u8, @intCast(cp))) else cp;
                const rhs = if (mode == .ignore_ascii and right <= 0x7F) std.ascii.toLower(@as(u8, @intCast(right))) else right;
                if (left != rhs) return null;
                cursor += length;
            }
            return cursor;
        },
    }
}

pub fn isSuffixOfWithCase(self: String, bytes: []const u8, mode: Case) bool {
    const length = self.utf8Len();
    if (length > bytes.len) return false;
    return self.eqlUtf8WithCase(bytes[bytes.len - length ..], mode);
}

pub fn isSubstringOfWithCase(self: String, bytes: []const u8, mode: Case) bool {
    if (mode == .exact and self.value == .borrowed)
        return std.mem.indexOf(u8, bytes, self.value.borrowed) != null;

    const length = self.utf8Len();
    if (length == 0) return true;
    if (length > bytes.len) return false;
    for (0..bytes.len - length + 1) |start| {
        if (bytes[start] & 0xC0 == 0x80) continue;
        if (self.prefixLength(bytes[start..], mode) != null) return true;
    }
    return false;
}

pub fn utf8Len(self: String) usize {
    return switch (self.value) {
        .borrowed => |bytes| bytes.len,
        .owned => |points| blk: {
            var length: usize = 0;
            for (points) |cp| length += std.unicode.utf8CodepointSequenceLength(cp) catch unreachable;
            break :blk length;
        },
    };
}

pub fn startsWith(self: String, prefix: []const u8) bool {
    return switch (self.value) {
        .borrowed => |bytes| std.mem.startsWith(u8, bytes, prefix),
        .owned => |code_points| blk: {
            if (code_points.len < prefix.len) break :blk false;
            for (code_points[0..prefix.len], prefix) |cp, byte| {
                if (cp != byte) break :blk false;
            }
            break :blk true;
        },
    };
}

/// Writes lowercase ASCII into buffer without allocating.
pub fn toAsciiLower(self: String, buffer: []u8) ?[]const u8 {
    switch (self.value) {
        inline else => |characters| {
            if (characters.len > buffer.len) return null;
            const result = buffer[0..characters.len];
            for (characters, result) |cp, *byte| {
                if (cp > 0x7f) return null;
                byte.* = std.ascii.toLower(@intCast(cp));
            }
            return result;
        },
    }
}

pub fn cloneDecoded(self: String, allocator: std.mem.Allocator) !String {
    return switch (self.value) {
        .borrowed => self,
        .owned => |value| fromDecoded(try allocator.dupe(u21, value)),
    };
}

pub fn freeDecoded(self: String, allocator: std.mem.Allocator) void {
    switch (self.value) {
        .borrowed => {},
        .owned => |value| allocator.free(value),
    }
}

pub fn len(self: *const String) usize {
    return switch (self.value) {
        .borrowed => |bytes| bytes.len,
        .owned => |code_points| code_points.len,
    };
}

pub fn codePoint(self: *const String, index: usize) ?u21 {
    return switch (self.value) {
        .borrowed => |bytes| if (index < bytes.len and bytes[index] < 0x80) bytes[index] else null,
        .owned => |code_points| if (index < code_points.len) code_points[index] else null,
    };
}

test "CSS String: comparisons" {
    const testing = std.testing;
    for ([_]String{ fromSource("éA"), fromDecoded(&.{ 0xE9, 'A' }) }) |string| {
        try testing.expect(string.eqlUtf8WithCase("éA", .exact));
        try testing.expect(!string.eqlUtf8WithCase("éa", .exact));
        try testing.expect(string.eqlUtf8WithCase("éa", .ignore_ascii));
        try testing.expect(!string.eqlUtf8WithCase("Éa", .ignore_ascii));
        try testing.expect(string.eqlUtf8WithCase("éa", .lower_self));
        try testing.expect(!string.eqlUtf8WithCase("éA", .lower_self));
        try testing.expectEqual(@as(?usize, 3), string.prefixLength("éAb", .exact));
        try testing.expect(string.prefixLength("é", .exact) == null);
        try testing.expect(string.isSuffixOfWithCase("xéa", .ignore_ascii));
        try testing.expect(!string.isSuffixOfWithCase("éAx", .exact));
        try testing.expect(string.isSubstringOfWithCase("xéAy", .exact));
        try testing.expect(string.isSubstringOfWithCase("xéay", .ignore_ascii));
        try testing.expect(!string.isSubstringOfWithCase("xÉay", .ignore_ascii));
    }
    for ([_]String{ fromSource(""), fromDecoded(&.{}) }) |empty| {
        try testing.expect(empty.eqlUtf8WithCase("", .exact));
        try testing.expect(!empty.eqlUtf8WithCase("x", .exact));
        try testing.expectEqual(@as(?usize, 0), empty.prefixLength("x", .exact));
        try testing.expect(empty.isSuffixOfWithCase("x", .exact));
        try testing.expect(empty.isSubstringOfWithCase("", .ignore_ascii));
        try testing.expect(empty.isSubstringOfWithCase("x", .exact));
    }
    // A byte-length suffix can start inside a multibyte code point.
    try testing.expect(!fromDecoded(&.{'a'}).isSuffixOfWithCase("é", .exact));
    try testing.expect(fromDecoded(&.{0x1F600}).isSubstringOfWithCase("x😀y", .exact));
}
