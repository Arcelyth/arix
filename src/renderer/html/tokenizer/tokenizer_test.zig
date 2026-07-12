const std = @import("std");
const testing = std.testing;
const Tokenizer = @import("Tokenizer.zig");
const TokenizerState = @import("state.zig");
const strale = @import("strale");
const BufferDeque = strale.BufferDeque;

test "Tokenizer Runnable Test" {
    const allocator = testing.allocator;

    var tok = Tokenizer.init(allocator, null);
    defer tok.deinit();

    var input = try BufferDeque(.utf8, .not_atomic, false).init(allocator);
    defer input.deinit();

    try input.pushBackSlice("Hello");

    try tok.step(&input);

    try testing.expectEqual(.Data, tok.state);
}
