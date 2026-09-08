const strale = @import("strale");
const std = @import("std");

pub fn BufferDeque(comptime format: strale.Format, comptime atomicity: strale.Atomicity, comptime use_global_alloc: bool) type {
    return struct {
        const Self = @This();
        const T = strale.Strale(format, atomicity, use_global_alloc);
        pub const CharType = switch (T.getFormat()) {
            .utf8 => u21,
            .byte => u8,
        };

        buffer: std.Deque(T),
        allocator: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) !Self {
            return Self{
                .buffer = try std.Deque(T).initCapacity(alloc, 16),
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            while (self.buffer.popFront()) |item| {
                var tmp = item;
                tmp.deinit();
            }
            self.buffer.deinit(self.allocator);
        }

        pub fn isEmpty(self: Self) bool {
            return self.buffer.len == 0;
        }

        /// Remove and return the `Strale` item from the front of the queue.
        ///
        /// Yield ownership of the returned item back to the caller. The caller
        /// becomes responsible for invoking `.deinit()` on the returned strin
        pub fn popFront(self: *Self) ?T {
            return self.buffer.popFront();
        }

        /// Remove and return the `Strale` item from the back of the queue.
        ///
        /// Yield ownership of the returned item back to the caller. The caller
        /// becomes responsible for invoking `.deinit()` on the returned strin
        pub fn popBack(self: *Self) ?T {
            return self.buffer.popBack();
        }

        /// Insert a `Strale` string at the front of the queue.
        ///
        /// If the item's length is 0, it will be instantly destroyed to save space.
        /// If the caller wishes to retain ownership, pass `item.clone()` instead.
        pub fn pushFront(self: *Self, item: T) error{OutOfMemory}!void {
            if (item.len() == 0) {
                var tmp = item;
                tmp.deinit();
                return;
            }
            try self.buffer.pushFront(self.allocator, item);
        }

        /// Insert a `Strale` string at the bask of the queue.
        ///
        /// If the item's length is 0, it will be instantly destroyed to save space.
        /// If the caller wishes to retain ownership, pass `item.clone()` instead.
        pub fn pushBack(self: *Self, item: T) error{OutOfMemory}!void {
            if (item.len() == 0) {
                var tmp = item;
                tmp.deinit();
                return;
            }

            try self.buffer.pushBack(self.allocator, item);
        }

        pub const pushFrontSlice = if (use_global_alloc)
            pushFrontSliceGlobal
        else
            pushFrontSliceAlloc;

        pub fn pushFrontSliceAlloc(self: *Self, slice: []const u8) !void {
            if (slice.len == 0) return;
            const s = try T.initSlice(self.allocator, slice);
            try self.buffer.pushFront(self.allocator, s);
        }

        pub fn pushFrontSliceGlobal(self: *Self, slice: []const u8) !void {
            if (slice.len == 0) return;
            const s = try T.initSlice(slice);
            try self.buffer.pushFront(self.allocator, s);
        }

        pub const pushBackSlice = if (use_global_alloc)
            pushBackSliceGlobal
        else
            pushBackSliceAlloc;

        pub fn pushBackSliceAlloc(self: *Self, slice: []const u8) !void {
            if (slice.len == 0) return;
            const s = try T.initSlice(self.allocator, slice);
            try self.buffer.pushBack(self.allocator, s);
        }

        pub fn pushBackSliceGlobal(self: *Self, slice: []const u8) !void {
            if (slice.len == 0) return;
            const s = try T.initSlice(slice);
            try self.buffer.pushBack(self.allocator, s);
        }

        /// Return the next character at the front of the queue without consuming it.
        pub fn peekChar(self: *Self) ?CharType {
            if (self.buffer.front()) |f| {
                return f.peek();
            }
            return null;
        }

        /// Return the next N character from the beginning of the queue without consuming it.
        pub fn peekCharN(self: Self, n: usize) ?CharType {
            if (self.buffer.len == 0) return null;

            var char_idx: usize = 0;
            var buf_idx: usize = 0;

            while (buf_idx < self.buffer.len) : (buf_idx += 1) {
                const buf = self.buffer.atPtr(buf_idx);
                const bytes = buf.slice();

                var byte_idx: usize = 0;
                while (byte_idx < bytes.len) {
                    if (CharType == u8) {
                        if (char_idx == n) return bytes[byte_idx];
                        byte_idx += 1;
                        char_idx += 1;
                    } else {
                        const len = std.unicode.utf8ByteSequenceLength(bytes[byte_idx]) catch return null;
                        if (char_idx == n) {
                            if (byte_idx + len > bytes.len) return null;
                            const cp = std.unicode.utf8Decode(bytes[byte_idx .. byte_idx + len]) catch return null;
                            return @as(u21, @intCast(cp));
                        }
                        byte_idx += len;
                        char_idx += 1;
                    }
                }
            }
            return null;
        }

        /// Consume and return the next character from the front of the queue.
        ///
        /// Return `null` when the entire queue runs out of characters.
        pub fn nextChar(self: *Self) ?CharType {
            while (self.buffer.frontPtr()) |f| {
                if (f.popFront()) |c| {
                    if (f.isEmpty()) {
                        if (self.buffer.popFront()) |item| {
                            var tmp = item;
                            tmp.deinit();
                        }
                    }
                    return c;
                } else {
                    if (self.buffer.popFront()) |item| {
                        var tmp = item;
                        tmp.deinit();
                    }
                }
            }

            return null;
        }

        /// Match the given byte sequence against the front of the deque.
        ///
        /// If every byte matches, the matched characters are consumed from the deque
        /// and this function returns `true`.
        /// If any byte differs or the deque does not contain enough characters,
        /// the deque remains unchanged and `false` is returned.
        ///
        /// Comparison is performed using the supplied equality function.
        pub fn consume(self: *Self, str: []const u8, eq: *const fn (u8, u8) bool) bool {
            if (str.len == 0) return true;
            if (self.buffer.len == 0) return false;

            var buffers_exhausted: usize = 0;
            var consumed_from_last: usize = 0;

            for (str) |pattern_byte| {
                if (buffers_exhausted >= self.buffer.len) return false;

                const buf = self.buffer.atPtr(buffers_exhausted);
                const buf_bytes = buf.slice();
                if (!eq(buf_bytes[consumed_from_last], pattern_byte)) return false;

                consumed_from_last += 1;
                if (consumed_from_last >= buf_bytes.len) {
                    buffers_exhausted += 1;
                    consumed_from_last = 0;
                }
            }

            var i: usize = 0;
            while (i < buffers_exhausted) : (i += 1) {
                if (self.buffer.popFront()) |item| {
                    var tmp = item;
                    tmp.deinit();
                }
            }

            if (consumed_from_last > 0) {
                if (self.buffer.frontPtr()) |f| {
                    f.dropFront(consumed_from_last);

                    if (f.isEmpty()) {
                        if (self.buffer.popFront()) |item| {
                            var tmp = item;
                            tmp.deinit();
                        }
                    }
                }
            }

            return true;
        }
    };
}

const testing = std.testing;

const Buffer = BufferDeque(.byte, .not_atomic, false);
const Str = strale.Strale(.byte, .not_atomic, false);

const BufferG = BufferDeque(.byte, .not_atomic, true);
const StrG = strale.Strale(.byte, .not_atomic, true);

fn asciiEq(a: u8, b: u8) bool {
    return a == b;
}

fn asciiEqIgnoreCase(a: u8, b: u8) bool {
    return std.ascii.toLower(a) == std.ascii.toLower(b);
}

test "pop" {
    const alloc = std.heap.page_allocator;
    var s = try Str.initSlice(alloc, "hello");
    defer s.deinit();
    const s2 = try Str.initSlice(alloc, "world");

    var buf = try Buffer.init(alloc);
    defer buf.deinit();
    try buf.pushBack(s.clone());
    // s2 only use once so move to buf
    try buf.pushBack(s2);
    try testing.expect(!buf.isEmpty());

    var result = buf.popFront().?;
    defer result.deinit();

    var result2 = buf.popFront().?;
    defer result2.deinit();

    try testing.expectEqualStrings("hello", result.slice());
    try testing.expectEqualStrings("world", result2.slice());
    try testing.expect(buf.isEmpty());
}

test "buffer peek next char" {
    const alloc = std.heap.page_allocator;
    var buf = try Buffer.init(alloc);
    defer buf.deinit();
    const s2 = try Str.initSlice(alloc, "hello");
    try buf.pushBack(s2);

    try buf.pushBackSlice("world");
    try testing.expect(!buf.isEmpty());

    try testing.expectEqual('h', buf.peekChar());
    try testing.expectEqual('w', buf.peekCharN(5));
    try testing.expectEqual('h', buf.nextChar());
    var f = buf.popFront().?;
    defer f.deinit();
    try testing.expectEqualStrings("hello", s2.slice());
    try testing.expectEqualStrings("ello", f.slice());
}

test "match exact" {
    const alloc = std.heap.page_allocator;
    var deque = try Buffer.init(alloc);
    defer deque.deinit();

    try deque.pushBackSlice("helloWoRld");

    try testing.expect(deque.consume("hello", asciiEq));
    try testing.expect(deque.consume("world", asciiEqIgnoreCase));
    try testing.expect(deque.isEmpty());
}

test "global: pop" {
    const alloc = std.heap.page_allocator;
    strale.setGlobalAlloc(alloc);
    var s = try StrG.initSlice("hello");
    defer s.deinit();
    const s2 = try StrG.initSlice("world");

    var buf = try BufferG.init(alloc);
    defer buf.deinit();
    try buf.pushBack(s.clone());
    // s2 only use once so move to buf
    try buf.pushBack(s2);
    try testing.expect(!buf.isEmpty());

    var result = buf.popFront().?;
    defer result.deinit();

    var result2 = buf.popFront().?;
    defer result2.deinit();

    try testing.expectEqualStrings("hello", result.slice());
    try testing.expectEqualStrings("world", result2.slice());
    try testing.expect(buf.isEmpty());
}
