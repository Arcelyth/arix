/// Benchmark for HTML parser which contains HTML tokenizer and tree_builder.
const Self = @This();
const std = @import("std");
const strale = @import("strale");
const Parser = @import("../renderer/html/Parser.zig");
const BufferDeque = @import("../renderer/utils/buffer_deque.zig").BufferDeque;
const Buffer = BufferDeque(.utf8, .not_atomic, true);

allocator: std.mem.Allocator,
arena: ?std.heap.ArenaAllocator = null,
buffer: ?Buffer = null,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn prepare(self: *Self, input: []const u8) !void {
    self.arena = std.heap.ArenaAllocator.init(self.allocator);
    const allocator = self.arena.?.allocator();
    strale.setGlobalAlloc(allocator);
    self.buffer = try Buffer.init(allocator);
    try self.buffer.?.pushBackSlice(input);
}

pub fn step(self: *Self) !usize {
    const allocator = self.arena.?.allocator();
    strale.setGlobalAlloc(allocator);
    const parser = try Parser.create(allocator, .{ .tokenizer = .{}, .tree_builder = .{} });
    defer parser.destroy();
    try parser.tokenizer.step_E(&self.buffer.?);
    std.mem.doNotOptimizeAway(parser.tree_builder.document);
    return parser.errors.items.len;
}

pub fn finish(self: *Self) void {
    self.buffer.?.deinit();
    self.buffer = null;
    self.arena.?.deinit();
    self.arena = null;
}
