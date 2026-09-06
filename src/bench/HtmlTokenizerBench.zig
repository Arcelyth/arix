const HtmlTokenizerBench = @This();

const std = @import("std");
const strale = @import("strale");
const Tokenizer = @import("../renderer/html/tokenizer/Tokenizer.zig");
const Token = @import("../renderer/html/tokenizer/token.zig").Token;
const TokenAdapter = @import("../renderer/html/tokenizer/TokenAdapter.zig");
const TokenizerError = @import("../renderer/html/tokenizer/error.zig").TokenizerError;
const TokenizerState = @import("../renderer/html/tokenizer/state.zig").TokenizerState;
const BufferDeque = strale.BufferDeque;

allocator: std.mem.Allocator,

const NullAdapter = struct {
    allocator: std.mem.Allocator,
    token_count: usize = 0,

    const vtable = TokenAdapter.VTable{
        .handleTokenFn = handleToken,
        .handleErrorFn = handleError,
        .adjustCurrentNodeAndNotInHtmlNamespace = adjustedCurrentNodeIsForeign,
    };

    fn adapter(self: *NullAdapter) TokenAdapter {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn handleToken(ptr: *anyopaque, token: Token) ?TokenizerState {
        const self: *NullAdapter = @ptrCast(@alignCast(ptr));
        var tk = token;
        std.mem.doNotOptimizeAway(tk);
        self.token_count += 1;
        tk.deinit(self.allocator);
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

pub fn init(allocator: std.mem.Allocator) HtmlTokenizerBench {
    return .{ .allocator = allocator };
}

pub fn step(self: *HtmlTokenizerBench, input: []const u8) !usize {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    strale.setGlobalAlloc(allocator);
    var sink = NullAdapter{ .allocator = allocator };
    var tokenizer = Tokenizer.init(allocator, sink.adapter(), .{});
    defer tokenizer.deinit();
    var buffer = try BufferDeque(.utf8, .not_atomic, true).init(allocator);
    defer buffer.deinit();
    try buffer.pushBackSlice(input);
    try tokenizer.step_E(&buffer);
    return sink.token_count;
}
