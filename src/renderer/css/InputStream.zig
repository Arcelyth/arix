const InputStream = @This();

const std = @import("std");
const ascii = @import("../utils/ascii.zig");

utf8_bytes: []const u8,
pos: usize = 0,

pub fn init(bytes: []const u8) InputStream {
    return .{ .utf8_bytes = bytes };
}

/// Get next filtered code point, see: https://drafts.csswg.org/css-syntax/#css-filter-code-points.
pub fn next(self: *InputStream) ?u21 {
    var cp = self.nextRaw() orelse return null;

    if (cp == '\r') {
        if (self.pos < self.utf8_bytes.len and self.utf8_bytes[self.pos] == '\n') self.pos += 1;
        cp = '\n';
    } else if (cp == 0x000C) {
        cp = '\n';
    }

    if (cp == 0x0000 or ascii.isSurrogate(u21, cp)) cp = 0xFFFD;

    return cp;
}

pub inline fn slice(self: *const InputStream, start: usize, end: usize) []const u8 {
    return self.utf8_bytes[start..end];
}

fn nextRaw(self: *InputStream) ?u21 {
    if (self.pos >= self.utf8_bytes.len) return null;

    // If code point is ASCII, return directly.
    const first = self.utf8_bytes[self.pos];
    if (first < 0x80) {
        self.pos += 1;
        return first;
    }

    const seq_len = std.unicode.utf8ByteSequenceLength(first) catch {
        // Handle invalid UTF-8 structure.
        self.pos += 1;
        return 0xFFFD;
    };

    if (self.pos + seq_len > self.utf8_bytes.len) {
        self.pos = self.utf8_bytes.len;
        return 0xFFFD;
    }

    const cp = std.unicode.utf8Decode(self.utf8_bytes[self.pos .. self.pos + seq_len]) catch {
        self.pos += 1;
        return 0xFFFD;
    };

    self.pos += seq_len;
    return cp;
}

const testing = std.testing;

test "CSS InputStream: handles invalid UTF-8" {
    const input = [_]u8{ 'a', 0xFF, 'b' };

    var pre = InputStream.init(&input);

    try testing.expectEqual(@as(u21, 'a'), pre.next().?);
    try testing.expectEqual(@as(u21, 0xFFFD), pre.next().?);
    try testing.expectEqual(@as(u21, 'b'), pre.next().?);
    try testing.expect(pre.next() == null);
}

test "CSS InputStream: handles CR CR LF" {
    const input = "\r\r\n";

    var pre = InputStream.init(input);

    try testing.expectEqual(@as(u21, '\n'), pre.next().?);
    try testing.expectEqual(@as(u21, '\n'), pre.next().?);
    try testing.expect(pre.next() == null);
}

test "CSS InputStream: source positions and slices" {
    var pre = InputStream.init("abc");
    const start = pre.pos;
    try testing.expectEqual(@as(u21, 'a'), pre.next().?);
    try testing.expectEqualStrings("a", pre.slice(start, pre.pos));
}
