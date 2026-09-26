/// String type for optimizing.
///
/// Most strings are represented as borrowed slices of the original
/// source buffer, avoiding allocations and copies on the common path.
/// Strings that require decoding are materialized into owned storage.
const String = @This();

const std = @import("std");

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
