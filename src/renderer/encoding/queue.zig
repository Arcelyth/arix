/// Implementation of I/O queue.
/// See https://encoding.spec.whatwg.org/
const std = @import("std");

pub fn IoQueue(comptime T: type) type {
    if (T != u8 and T != u21) @compileError("encoding queues contain bytes or scalar values");
    return struct {
        const Self = @This();

        items: std.ArrayList(T) = .empty,
        index: usize = 0,
        ended: bool = false,

        pub fn fromSlice(allocator: std.mem.Allocator, input: []const T) !Self {
            var self: Self = .{};
            try self.pushSlice(allocator, input);
            self.ended = true;
            return self;
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.items.deinit(allocator);
        }

        pub fn read(self: *Self) error{NeedInput}!?T {
            if (self.index == self.items.items.len) {
                if (self.ended) return null;
                // Wait until input comes.
                return error.NeedInput;
            }
            const item = self.items.items[self.index];
            self.index += 1;
            return item;
        }

        pub fn readMany(self: *Self, number: usize) error{NeedInput}![]const T {
            const result = try self.peek(number);
            self.index += result.len;
            return result;
        }

        pub fn peek(self: *const Self, number: usize) error{NeedInput}![]const T {
            const remaining = self.items.items[self.index..];
            if (remaining.len < number and !self.ended) return error.NeedInput;
            return remaining[0..@min(number, remaining.len)];
        }

        pub fn readAll(self: *Self) error{NeedInput}![]const T {
            if (!self.ended) return error.NeedInput;
            return self.readMany(self.items.items.len - self.index);
        }

        pub fn toOwnedSlice(self: *Self, allocator: std.mem.Allocator) ![]T {
            if (!self.ended) return error.NeedInput;
            const result = try allocator.dupe(T, self.items.items[self.index..]);
            self.index = self.items.items.len;
            return result;
        }

        pub fn push(self: *Self, allocator: std.mem.Allocator, item: ?T) !void {
            if (item) |value|
                try self.pushSlice(allocator, &.{value})
            else
                self.ended = true;
        }

        pub fn pushSlice(self: *Self, allocator: std.mem.Allocator, items: []const T) !void {
            // If the whole queue has been consumed, clear it and retain cap.
            if (self.index == self.items.items.len) {
                self.items.clearRetainingCapacity();
                self.index = 0;
            }
            try self.items.appendSlice(allocator, items);
        }

        pub fn restore(self: *Self, allocator: std.mem.Allocator, item: T) !void {
            try self.restoreSlice(allocator, &.{item});
        }

        pub fn restoreSlice(self: *Self, allocator: std.mem.Allocator, items: []const T) !void {
            if (items.len <= self.index) {
                self.index -= items.len;
                @memcpy(self.items.items[self.index..][0..items.len], items);
            } else {
                try self.items.insertSlice(allocator, self.index, items);
            }
        }
    };
}

const testing = std.testing;

test "encoding queue: basic operations" {
    var input = try IoQueue(u8).fromSlice(testing.allocator, "abc");
    defer input.deinit(testing.allocator);

    try testing.expectEqualStrings("", try input.peek(0));
    try testing.expectEqualStrings("ab", try input.peek(2));
    try testing.expectEqualStrings("abc", try input.peek(99));
    try testing.expectEqual(0, input.index);
    try testing.expectEqualStrings("", try input.readMany(0));
    try testing.expectEqual(@as(?u8, 'a'), try input.read());
    try testing.expectEqualStrings("bc", try input.readMany(99));
    try testing.expectEqualStrings("", try input.peek(1));
    try testing.expectEqualStrings("", try input.readMany(1));
    try testing.expectEqual(@as(?u8, null), try input.read());
    try testing.expectEqual(@as(?u8, null), try input.read());
}

test "encoding queue: streaming waits for enough input or end-of-queue" {
    var input: IoQueue(u8) = .{};
    defer input.deinit(testing.allocator);

    try testing.expectEqualStrings("", try input.peek(0));
    try testing.expectEqualStrings("", try input.readMany(0));
    try testing.expectError(error.NeedInput, input.read());
    try testing.expectError(error.NeedInput, input.peek(1));
    try testing.expectError(error.NeedInput, input.readAll());
    try input.pushSlice(testing.allocator, "ab");
    try testing.expectError(error.NeedInput, input.peek(3));
    try testing.expectError(error.NeedInput, input.readMany(3));
    try testing.expectEqual(@as(usize, 0), input.index);
    try input.push(testing.allocator, 'c');
    try testing.expectEqualStrings("abc", try input.readMany(3));
    try testing.expectError(error.NeedInput, input.read());
    try input.pushSlice(testing.allocator, "de");
    try testing.expectError(error.NeedInput, input.readAll());
    try input.push(testing.allocator, null);
    try testing.expectEqualStrings("de", try input.readAll());
    try testing.expectEqual(@as(?u8, null), try input.read());
}
