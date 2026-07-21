const std = @import("std");
const testing = std.testing;
const Tokenizer = @import("Tokenizer.zig");
const TokenizerState = @import("state.zig");
const strale = @import("strale");
const BufferDeque = strale.BufferDeque;
const TestIngester = @import("TestIngester.zig");
const TokenIngester = @import("TokenIngester.zig");
const token = @import("token.zig");
const Token = token.Token;

//test "tokenizer test" {
//    std.testing.log_level = .debug;
//    const allocator = testing.allocator;
//    var ti = TestIngester.init(allocator);
//    defer ti.deinit();
//    const ingester = TokenIngester.init(
//        &ti,
//        TestIngester.handleToken,
//    );
//    strale.setGlobalAlloc(allocator);
//    var tok = Tokenizer.init(allocator, ingester, null);
//    defer tok.deinit();
//
//    var input = try BufferDeque(.utf8, .not_atomic, true).init(allocator);
//    defer input.deinit();
//
//    try input.pushBackSlice("Hello");
//
//    try tok.step_E(&input);
//
//    try testing.expectEqual(.Data, tok.state);
//}
