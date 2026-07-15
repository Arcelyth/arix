const std = @import("std");
const testing = std.testing;
const Tokenizer = @import("Tokenizer.zig");
const TokenizerState = @import("state.zig");
const strale = @import("strale");
const BufferDeque = strale.BufferDeque;

test "Tokenizer Runnable Test" {
    const allocator = testing.allocator;
    strale.setGlobalAlloc(allocator);
    var tok = Tokenizer.init(allocator, null);
    defer tok.deinit();

    var input = try BufferDeque(.utf8, .not_atomic, true).init(allocator);
    defer input.deinit();

    try input.pushBackSlice("Hello");

    try tok.step_E(&input);

    try testing.expectEqual(.Data, tok.state);
}
