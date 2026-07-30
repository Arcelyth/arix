/// A simple ingester for testing.
const TestIngester = @This();

const std = @import("std");
const Token = @import("token.zig").Token;

allocator: std.mem.Allocator,
tokens: std.ArrayList(Token),

pub fn init(alloc: std.mem.Allocator) TestIngester {
    return .{
        .allocator = alloc,
        .tokens = .empty,
    };
}

pub fn deinit(self: *TestIngester) void {
    for (self.tokens.items) |*tok| {
        tok.deinit(self.allocator);
    }

    self.tokens.deinit(self.allocator);
}

pub fn handleToken(self: *TestIngester, token: Token) void {
    self.tokens.append(self.allocator, token) catch unreachable;
}
