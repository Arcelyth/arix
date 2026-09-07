const Self = @This();
const std = @import("std");
const Tokenizer = @import("../renderer/css/Tokenizer.zig");
const Parser = @import("../renderer/css/Parser.zig");
const TokenStream = @import("../renderer/css/TokenStream.zig");
const cloneToken = @import("../renderer/css/token.zig").cloneToken;

allocator: std.mem.Allocator,
arena: ?std.heap.ArenaAllocator = null,
stream: ?TokenStream = null,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn prepare(self: *Self, input: []const u8) !void {
    self.arena = std.heap.ArenaAllocator.init(self.allocator);
    const allocator = self.arena.?.allocator();
    var tokenizer = Tokenizer.init(allocator, input);
    defer tokenizer.deinit();
    var items: std.ArrayList(TokenStream.Item) = .empty;
    while (true) {
        const token = tokenizer.consume(false);
        if (token == .eof) break;
        try items.append(allocator, .{ .token = try cloneToken(allocator, token) });
    }
    self.stream = TokenStream.init(allocator, items.items);
}

pub fn step(self: *Self) !usize {
    var parser = Parser.init(self.arena.?.allocator(), &self.stream.?);
    const stylesheet = try parser.parseStylesheet();
    std.mem.doNotOptimizeAway(stylesheet.rules.ptr);
    return stylesheet.rules.len;
}

pub fn finish(self: *Self) void {
    self.stream.?.deinit();
    self.stream = null;
    self.arena.?.deinit();
    self.arena = null;
}
