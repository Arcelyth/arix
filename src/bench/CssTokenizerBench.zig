const Self = @This();
const std = @import("std");
const Tokenizer = @import("../renderer/css/Tokenizer.zig");

allocator: std.mem.Allocator,
arena: ?std.heap.ArenaAllocator = null,
input: []const u8 = &.{},

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn prepare(self: *Self, input: []const u8) !void {
    self.arena = std.heap.ArenaAllocator.init(self.allocator);
    self.input = input;
}

pub fn step(self: *Self) !usize {
    var tokenizer = Tokenizer.init(self.arena.?.allocator(), self.input);
    defer tokenizer.deinit();
    var count: usize = 0;
    while (true) {
        const token = tokenizer.consume(false);
        std.mem.doNotOptimizeAway(token);
        if (token == .eof) return count;
        count += 1;
    }
}

pub fn finish(self: *Self) void {
    self.arena.?.deinit();
    self.arena = null;
}
