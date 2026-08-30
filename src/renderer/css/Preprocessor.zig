const Preprocessor = @This();

const std = @import("std");
const ascii = @import("../utils/ascii.zig");

utf8_bytes: []const u8,
index: usize = 0,
peeked_cp: ?u21 = null,

pub fn init(bytes: []const u8) Preprocessor {
    return .{ .utf8_bytes = bytes };
}

/// Get next filtered code point, see: https://drafts.csswg.org/css-syntax/#css-filter-code-points.
pub fn next(self: *Preprocessor) ?u21 {
    var cp = self.nextRaw() orelse return null;

    if (cp == '\r') {
        const next_cp = self.nextRaw();
        if (next_cp == '\n') {
            cp = '\n';
        } else {
            self.peeked_cp = next_cp;
            cp = '\n';
        }
    } else if (cp == 0x000C) {
        cp = '\n';
    }

    if (cp == 0x0000 or ascii.isSurrogate(u21, cp)) cp = 0xFFFD;

    return cp;
}

fn nextRaw(self: *Preprocessor) ?u21 {
    if (self.peeked_cp) |cp| {
        self.peeked_cp = null;
        return cp;
    }

    if (self.index >= self.utf8_bytes.len) return null;

    const seq_len = std.unicode.utf8ByteSequenceLength(self.utf8_bytes[self.index]) catch {
        // Handle invalid UTF-8 structure.
        self.index += 1;
        return 0xFFFD;
    };

    if (self.index + seq_len > self.utf8_bytes.len) {
        self.index = self.utf8_bytes.len;
        return 0xFFFD;
    }

    const cp = std.unicode.utf8Decode(self.utf8_bytes[self.index .. self.index + seq_len]) catch {
        self.index += 1;
        return 0xFFFD;
    };

    self.index += seq_len;
    return cp;
}

test "CSS Preprocessor: handles invalid UTF-8" {
    const testing = std.testing;

    const input = [_]u8{ 'a', 0xFF, 'b' };

    var pre = Preprocessor.init(&input);

    try testing.expectEqual(@as(u21, 'a'), pre.next().?);
    try testing.expectEqual(@as(u21, 0xFFFD), pre.next().?);
    try testing.expectEqual(@as(u21, 'b'), pre.next().?);
    try testing.expect(pre.next() == null);
}

test "CSS Preprocessor: handles CR CR LF" {
    const testing = std.testing;

    const input = "\r\r\n";

    var pre = Preprocessor.init(input);

    try testing.expectEqual(@as(u21, '\n'), pre.next().?);
    try testing.expectEqual(@as(u21, '\n'), pre.next().?);
    try testing.expect(pre.next() == null);
}
