const Tokenizer = @This();

const std = @import("std");
const InputStream = @import("InputStream.zig");

allocator: std.mem.Allocator,
stream: InputStream,

/// Fixed 3-code-point Ring-buffer lookahead. 
lookahead: [3]u21 = undefined,
/// UTF-8 byte length of each buffered code point.
lookahead_byte_len: [3]u3 = undefined,
lookahead_head: u2 = 0,
lookahead_len: u2 = 0,
current: ?u21 = null,
reconsume_current: bool = false,
/// Reused for decoded escapes and replacement characters. Common tokens
/// borrow the original input and never touch this buffer.
scratch: std.ArrayList(u8) = .empty,

pub fn init(alloc: std.mem.Allocator, input_stream: []const u8) Tokenizer {
    return .{
        .allocator = alloc,
        .stream = InputStream.init(input_stream),
    };
}

pub fn deinit(self: *Tokenizer) void {
    self.scratch.deinit(self.allocator);
}

pub inline fn resetScratch(self: *Tokenizer) void {
    self.scratch.clearRetainingCapacity();
}

/// Consume the next filtered input code point.
pub inline fn next(self: *Tokenizer) ?u21 {
    if (self.reconsume_current) {
        self.reconsume_current = false;
        return self.current;
    }

    const code_point = if (self.lookahead_len == 0)
        self.stream.next()
    else blk: {
        const buffered = self.lookahead[self.lookahead_head];
        self.lookahead_head += 1;
        if (self.lookahead_head == 3) self.lookahead_head = 0;
        self.lookahead_len -= 1;
        break :blk buffered;
    };
    self.current = code_point;
    return code_point;
}

/// Return one of the next three input code points without consuming it.
pub fn peek(self: *Tokenizer, comptime offset: u2) ?u21 {
    comptime if (offset > 2) @compileError("lookahead is limited to offsets 0...2");

    const buffered_offset: u2 = if (self.reconsume_current) blk: {
        if (offset == 0) return self.current;
        break :blk offset - 1;
    } else offset;

    while (self.lookahead_len <= buffered_offset) {
        const before = self.stream.pos;
        const cp = self.stream.next() orelse return null;
        const index = ringIndex(self.lookahead_head, self.lookahead_len);
        self.lookahead[index] = cp;
        self.lookahead_byte_len[index] = @intCast(self.stream.pos - before);
        self.lookahead_len += 1;
    }
    return self.lookahead[ringIndex(self.lookahead_head, buffered_offset)];
}

pub inline fn reconsume(self: *Tokenizer) void {
    self.reconsume_current = true;
}

/// Logical byte position, excluding code points buffered by lookahead.
pub fn position(self: *const Tokenizer) usize {
    var buffered_bytes: usize = 0;
    var offset: u2 = 0;
    while (offset < self.lookahead_len) : (offset += 1) {
        buffered_bytes += self.lookahead_byte_len[ringIndex(self.lookahead_head, offset)];
    }
    return self.stream.pos - buffered_bytes;
}

inline fn ringIndex(head: u2, offset: u2) usize {
    var index: u3 = @as(u3, head) + @as(u3, offset);
    if (index >= 3) index -= 3;
    return index;
}

test "CSS Tokenizer: caches three-code-point lookahead" {
    const testing = std.testing;

    var tokenizer = Tokenizer.init(testing.allocator, "aé\r\nb");
    defer tokenizer.deinit();

    try testing.expectEqual(@as(u21, 'a'), tokenizer.peek(0).?);
    try testing.expectEqual(@as(u21, 'é'), tokenizer.peek(1).?);
    try testing.expectEqual(@as(u21, '\n'), tokenizer.peek(2).?);
    try testing.expectEqual(@as(usize, 0), tokenizer.position());
    try testing.expectEqual(@as(u21, 'a'), tokenizer.next().?);
    try testing.expectEqual(@as(usize, 1), tokenizer.position());
    tokenizer.reconsume();
    try testing.expectEqual(@as(u21, 'a'), tokenizer.peek(0).?);
    try testing.expectEqual(@as(u21, 'é'), tokenizer.peek(1).?);
    try testing.expectEqual(@as(u21, 'a'), tokenizer.next().?);
    try testing.expectEqual(@as(u21, 'é'), tokenizer.next().?);
    try testing.expectEqual(@as(u21, 'b'), tokenizer.peek(1).?);
    try testing.expectEqual(@as(u21, '\n'), tokenizer.next().?);
    try testing.expectEqual(@as(u21, 'b'), tokenizer.next().?);
    try testing.expect(tokenizer.peek(0) == null);
}
