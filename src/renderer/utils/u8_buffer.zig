pub const BufferError = error{
    Overflow,
};

pub fn U8Buffer(comptime size: usize) type {
    return struct {
        const Self = @This();
        buf: [size]u8 = undefined,
        len: usize = 0,

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn append(self: *Self, c: u8) !void {
            if (self.len >= size) return BufferError.Overflow;
            self.buf[self.len] = c;
            self.len += 1;
        }

        pub fn asSlice(self: *const Self) []const u8 {
            return self.buf[0..self.len];
        }
    };
}

const std = @import("std");
const testing = std.testing;

test "U8Buffer basic" {
    var buf = U8Buffer(4){};

    try testing.expectEqual(0, buf.len);
    try testing.expectEqualStrings("", buf.asSlice());
    try buf.append('a');
    try buf.append('b');
    try buf.append('c');

    try testing.expectEqual(3, buf.len);
    try testing.expectEqualStrings("abc", buf.asSlice());

    buf.clear();
    try testing.expectEqual(0, buf.len);
    try testing.expectEqualStrings("", buf.asSlice());
}

test "U8Buffer overflow" {
    var buf = U8Buffer(2){};

    try buf.append('a');
    try buf.append('b');

    try testing.expectError(BufferError.Overflow, buf.append('c'));

    try testing.expectEqual(2, buf.len);
    try testing.expectEqualStrings("ab", buf.asSlice());
}
