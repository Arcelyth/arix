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

        pub const PopUntilResult = union(enum) {
            /// The first byte is a delimiter and was not consumed.
            from_set: CharType,
            /// A run of non-delimiter bytes was consumed.
            /// `delimiter` is the first delimiter after the consumed run, if any.
            not_from_set: struct {
                value: T,
                delimiter: ?CharType,
            },
        };

        pub const FrontRun = struct {
            bytes: []const u8,
            delimiter: ?CharType,
        };

        inline fn isInputErrorByte(byte: u8) bool {
            return byte <= 0x08 or byte == 0x0B or
                (byte >= 0x0E and byte <= 0x1F) or byte == 0x7F;
        }

        /// Find the first byte that belongs to `set` or, when enabled, is an /// input-error byte.
        /// Using SIMD to scan multiple bytes at once.
        inline fn indexOfAny(bytes: []const u8, comptime set: []const u8, comptime input_errors: bool) usize {
            const table = comptime table: {
                var value = std.StaticBitSet(256).initEmpty();
                for (set) |char| value.set(char);
                break :table value;
            };
            if (set.len <= 16) {
                const Vector = @Vector(16, u8);
                const BoolVector = @Vector(16, bool);
                var offset: usize = 0;

                while (offset + 16 <= bytes.len) : (offset += 16) {
                    const block: Vector = bytes[offset..][0..16].*;
                    var matches: BoolVector = @splat(false);
                    inline for (set) |delimiter| {
                        matches = matches | (block == @as(Vector, @splat(delimiter)));
                    }
                    if (input_errors) {
                        matches = matches |
                            (block <= @as(Vector, @splat(0x08))) |
                            (block == @as(Vector, @splat(0x0B))) |
                            ((block >= @as(Vector, @splat(0x0E))) &
                                (block <= @as(Vector, @splat(0x1F)))) |
                            (block == @as(Vector, @splat(0x7F)));
                    }
                    if (@reduce(.Or, matches)) {
                        for (bytes[offset..][0..16], 0..) |byte, i| {
                            if (table.isSet(byte) or (input_errors and isInputErrorByte(byte)))
                                return offset + i;
                        }
                    }
                }

                for (bytes[offset..], offset..) |byte, i| {
                    if (table.isSet(byte) or (input_errors and isInputErrorByte(byte))) return i;
                }
                return bytes.len;
            }

            // For larger delimiter sets, a bitset lookup is cheaper than performing
            // one SIMD comparison for every delimiter.
            for (bytes, 0..) |byte, i| {
                if (table.isSet(byte) or (input_errors and isInputErrorByte(byte))) return i;
            }
            return bytes.len;
        }

        /// Return the maximal byte run in the front buffer before a character
        /// in `set`. The returned bytes borrow from the deque and remain valid
        /// until the front buffer is mutated.
        fn peekUntilImpl(self: *Self, comptime set: []const u8, comptime input_errors: bool) ?FrontRun {
            while (self.buffer.frontPtr()) |front| {
                const bytes = front.slice();
                if (bytes.len == 0) {
                    var empty = self.buffer.popFront().?;
                    empty.deinit();
                    continue;
                }

                const index = indexOfAny(bytes, set, input_errors);
                return .{
                    .bytes = bytes[0..index],
                    .delimiter = if (index < bytes.len) @intCast(bytes[index]) else null,
                };
            }
            return null;
        }

        pub fn peekUntil(self: *Self, comptime set: []const u8) ?FrontRun {
            return self.peekUntilImpl(set, false);
        }

        pub fn peekUntilWithInputErrors(self: *Self, comptime set: []const u8) ?FrontRun {
            return self.peekUntilImpl(set, true);
        }

        /// Return the maximal ASCII run before a byte in `set`, an uppercase
        /// ASCII letter, or a non-ASCII byte. This lets tokenizer name states
        /// append ordinary bytes in one operation while retaining their scalar
        /// handling for case folding and exceptional code points.
        fn peekAsciiNameRunImpl(self: *Self, comptime set: []const u8, comptime input_errors: bool) ?FrontRun {
            const table = comptime table: {
                var value = std.StaticBitSet(256).initEmpty();
                for (set) |char| value.set(char);
                break :table value;
            };

            while (self.buffer.frontPtr()) |front| {
                const bytes = front.slice();
                if (bytes.len == 0) {
                    var empty = self.buffer.popFront().?;
                    empty.deinit();
                    continue;
                }

                for (bytes, 0..) |byte, index| {
                    if (byte >= 0x80 or std.ascii.isUpper(byte) or
                        table.isSet(byte) or (input_errors and isInputErrorByte(byte)))
                    {
                        return .{
                            .bytes = bytes[0..index],
                            .delimiter = if (byte < 0x80) @intCast(byte) else null,
                        };
                    }
                }
                return .{ .bytes = bytes, .delimiter = null };
            }
            return null;
        }

        pub fn peekAsciiNameRun(self: *Self, comptime set: []const u8) ?FrontRun {
            return self.peekAsciiNameRunImpl(set, false);
        }

        pub fn peekAsciiNameRunWithInputErrors(self: *Self, comptime set: []const u8) ?FrontRun {
            return self.peekAsciiNameRunImpl(set, true);
        }

        /// Consume bytes previously returned by `peekUntil`.
        pub fn consumeFrontBytes(self: *Self, count: usize) void {
            if (count == 0) return;
            const front = self.buffer.frontPtr() orelse unreachable;
            if (count == front.len()) {
                var consumed = self.buffer.popFront().?;
                consumed.deinit();
                return;
            }
            std.debug.assert(count < front.len());
            front.dropFrontBytes(count);
        }

        /// Consume the maximal byte run before the next ASCII character in
        /// `set`. A matching character is returned without being consumed.
        fn popUntilImpl(self: *Self, comptime set: []const u8, comptime input_errors: bool) ?PopUntilResult {
            while (self.buffer.frontPtr()) |front| {
                const bytes = front.slice();
                if (bytes.len == 0) {
                    var empty = self.buffer.popFront().?;
                    empty.deinit();
                    continue;
                }

                const table = comptime table: {
                    var value = std.StaticBitSet(256).initEmpty();
                    for (set) |char| value.set(char);
                    break :table value;
                };
                const index = indexOfAny(bytes, set, input_errors);
                if (index == 0)
                    return .{ .from_set = @intCast(bytes[0]) };

                if (index == bytes.len) {
                    const value = self.buffer.popFront().?;
                    const delimiter = if (self.peekChar()) |char|
                        if (char <= std.math.maxInt(u8) and table.isSet(@intCast(char)))
                            char
                        else
                            null
                    else
                        null;
                    return .{ .not_from_set = .{ .value = value, .delimiter = delimiter } };
                }

                const delimiter: CharType = @intCast(bytes[index]);
                const run = front.substr(0, @intCast(index));
                front.dropFrontBytes(index);
                return .{ .not_from_set = .{ .value = run, .delimiter = delimiter } };
            }
            return null;
        }

        pub fn popUntil(self: *Self, comptime set: []const u8) ?PopUntilResult {
            return self.popUntilImpl(set, false);
        }

        pub fn popUntilWithInputErrors(self: *Self, comptime set: []const u8) ?PopUntilResult {
            return self.popUntilImpl(set, true);
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

        /// Consume the front character without decoding and returning it.
        ///
        /// Use this after `peekChar` when the caller already holds the decoded
        /// character.
        pub fn discardChar(self: *Self) bool {
            while (self.buffer.frontPtr()) |front| {
                const bytes = front.slice();
                if (bytes.len == 0) {
                    var empty = self.buffer.popFront().?;
                    empty.deinit();
                    continue;
                }

                const byte_len = if (CharType == u8)
                    1
                else
                    @min(std.unicode.utf8ByteSequenceLength(bytes[0]) catch 1, bytes.len);
                front.dropFrontBytes(byte_len);

                if (front.isEmpty()) {
                    var empty = self.buffer.popFront().?;
                    empty.deinit();
                }
                return true;
            }
            return false;
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
const Utf8Buffer = BufferDeque(.utf8, .not_atomic, false);

fn asciiEq(a: u8, b: u8) bool {
    return a == b;
}

fn asciiEqIgnoreCase(a: u8, b: u8) bool {
    return std.ascii.toLower(a) == std.ascii.toLower(b);
}

test "utils BufferDeque: pop" {
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

test "utils BufferDeque: buffer peek next char" {
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

test "utils BufferDeque: match exact" {
    const alloc = std.heap.page_allocator;
    var deque = try Buffer.init(alloc);
    defer deque.deinit();

    try deque.pushBackSlice("helloWoRld");

    try testing.expect(deque.consume("hello", asciiEq));
    try testing.expect(deque.consume("world", asciiEqIgnoreCase));
    try testing.expect(deque.isEmpty());
}

test "utils BufferDeque: global pop" {
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

test "utils BufferDeque: pop until" {
    const alloc = std.heap.page_allocator;
    var deque = try Buffer.init(alloc);
    defer deque.deinit();

    try deque.pushBackSlice("hello&world");

    const hello_run = (deque.popUntil(&.{ '\r', '&', '\n' }) orelse return error.TestUnexpectedResult).not_from_set;
    try testing.expectEqual('&', hello_run.delimiter.?);
    var hello = hello_run.value;
    defer hello.deinit();
    try testing.expectEqualStrings("hello", hello.slice());

    const ampersand = (deque.popUntil("\x00&\nab") orelse return error.TestUnexpectedResult).from_set;
    try testing.expectEqual('&', ampersand);
    try testing.expectEqual('&', deque.nextChar().?);

    const world_run = (deque.popUntil("\r\x00&<\n") orelse return error.TestUnexpectedResult).not_from_set;
    try testing.expect(world_run.delimiter == null);
    var world = world_run.value;
    defer world.deinit();
    try testing.expectEqualStrings("world", world.slice());
    try testing.expect(deque.popUntil("\r\x00&<\n") == null);
}

test "utils BufferDeque: peek until returns a borrowed run" {
    const alloc = std.heap.page_allocator;
    var deque = try Buffer.init(alloc);
    defer deque.deinit();

    try deque.pushBackSlice("hello&world");
    const run = deque.peekUntil("&<").?;
    try testing.expectEqualStrings("hello", run.bytes);
    try testing.expectEqual('&', run.delimiter.?);
    try testing.expectEqual('h', deque.peekChar().?);

    deque.consumeFrontBytes(run.bytes.len);
    try testing.expectEqual('&', deque.peekChar().?);
}

test "utils BufferDeque: input-error scan stops at ASCII controls" {
    const alloc = std.heap.page_allocator;
    var deque = try Buffer.init(alloc);
    defer deque.deinit();

    try deque.pushBackSlice("abcdefghijklmnop\x07tail");
    const run = deque.peekUntilWithInputErrors("&<").?;
    try testing.expectEqualStrings("abcdefghijklmnop", run.bytes);
    try testing.expectEqual(0x07, run.delimiter.?);
}

test "utils BufferDeque: discard peeked UTF-8 character" {
    const alloc = std.heap.page_allocator;
    var deque = try Utf8Buffer.init(alloc);
    defer deque.deinit();

    try deque.pushBackSlice("A\u{4E2D}\u{1F642}");

    try testing.expectEqual('A', deque.peekChar().?);
    try testing.expect(deque.discardChar());
    try testing.expectEqual('\u{4E2D}', deque.peekChar().?);
    try testing.expect(deque.discardChar());
    try testing.expectEqual('\u{1F642}', deque.peekChar().?);
    try testing.expect(deque.discardChar());
    try testing.expect(!deque.discardChar());
    try testing.expect(deque.isEmpty());
}

test "utils BufferDeque: discard character crosses buffer boundary" {
    const alloc = std.heap.page_allocator;
    var deque = try Utf8Buffer.init(alloc);
    defer deque.deinit();

    try deque.pushBackSlice("\u{4E2D}");
    try deque.pushBackSlice("B");

    try testing.expectEqual('\u{4E2D}', deque.peekChar().?);
    try testing.expect(deque.discardChar());
    try testing.expectEqual('B', deque.peekChar().?);
    try testing.expect(deque.discardChar());
    try testing.expect(deque.isEmpty());
}

test "utils BufferDeque: ASCII name run stops before exceptional bytes" {
    const alloc = std.heap.page_allocator;
    var deque = try Utf8Buffer.init(alloc);
    defer deque.deinit();

    try deque.pushBackSlice("custom-nameUpper");
    const lower = deque.peekAsciiNameRun("\t\r\n\x0C /\x00>").?;
    try testing.expectEqualStrings("custom-name", lower.bytes);
    try testing.expectEqual('U', lower.delimiter.?);

    deque.consumeFrontBytes(lower.bytes.len);
    try testing.expectEqual('U', deque.peekChar().?);
}

test "utils BufferDeque: ASCII name run stops before non-ASCII" {
    const alloc = std.heap.page_allocator;
    var deque = try Utf8Buffer.init(alloc);
    defer deque.deinit();

    try deque.pushBackSlice("name\u{4E2D}");
    const run = deque.peekAsciiNameRun("\t\r\n\x0C /\x00>").?;
    try testing.expectEqualStrings("name", run.bytes);
    try testing.expect(run.delimiter == null);
}
