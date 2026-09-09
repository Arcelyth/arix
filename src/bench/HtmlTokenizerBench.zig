/// Benchmark for HTML tokenizer.
const Self = @This();
const std = @import("std");
const strale = @import("strale");
const Tokenizer = @import("../renderer/html/tokenizer/Tokenizer.zig");
const Token = @import("../renderer/html/tokenizer/token.zig").Token;
const TokenAdapter = @import("../renderer/html/tokenizer/TokenAdapter.zig");
const TokenizerError = @import("../renderer/html/tokenizer/error.zig").TokenizerError;
const TokenizerState = @import("../renderer/html/tokenizer/state.zig").TokenizerState;
const BufferDeque = @import("../renderer/utils/buffer_deque.zig").BufferDeque;
const Buffer = BufferDeque(.utf8, .not_atomic, true);

allocator: std.mem.Allocator,
arena: ?std.heap.ArenaAllocator = null,
buffer: ?Buffer = null,
adapter: NullAdapter = .{},

/// This adapter do nothing for benching.
const NullAdapter = struct {
    allocator: ?std.mem.Allocator = null,
    token_count: usize = 0,

    const vtable = TokenAdapter.VTable{
        .handleTokenFn = handleToken,
        .handleErrorFn = handleError,
        .adjustCurrentNodeAndNotInHtmlNamespace = adjustedCurrentNodeIsForeign,
    };

    fn adapter(self: *NullAdapter) TokenAdapter {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn handleToken(ptr: *anyopaque, value: Token) ?TokenizerState {
        const self: *NullAdapter = @ptrCast(@alignCast(ptr));
        var token = value;
        std.mem.doNotOptimizeAway(token);
        self.token_count += 1;
        token.deinit(self.allocator.?);
        return null;
    }

    fn handleError(ptr: *anyopaque, err: TokenizerError, line: usize) void {
        std.mem.doNotOptimizeAway(ptr);
        std.mem.doNotOptimizeAway(err);
        std.mem.doNotOptimizeAway(line);
    }

    fn adjustedCurrentNodeIsForeign(ptr: *anyopaque) bool {
        std.mem.doNotOptimizeAway(ptr);
        return false;
    }
};

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn prepare(self: *Self, input: []const u8) !void {
    self.arena = std.heap.ArenaAllocator.init(self.allocator);
    const allocator = self.arena.?.allocator();
    strale.setGlobalAlloc(allocator);
    self.adapter = .{ .allocator = allocator };
    self.buffer = try Buffer.init(allocator);
    try self.buffer.?.pushBackSlice(input);
    strale.setGlobalAlloc(allocator);
}

pub fn step(self: *Self) !usize {
    const allocator = self.arena.?.allocator();
    var tokenizer = Tokenizer.init(allocator, self.adapter.adapter(), .{});
    defer tokenizer.deinit();
    try tokenizer.step_E(&self.buffer.?);
    return self.adapter.token_count;
}

pub fn finish(self: *Self) void {
    self.buffer.?.deinit();
    self.buffer = null;
    self.arena.?.deinit();
    self.arena = null;
}
