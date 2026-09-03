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
