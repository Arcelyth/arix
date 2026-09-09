/// A simple adapter for testing.
const TestAdapter = @This();

const std = @import("std");
const Token = @import("token.zig").Token;
const Vtable = @import("TokenAdapter.zig").VTable;
const TokenAdapter = @import("TokenAdapter.zig");
const e = @import("error.zig");
const tokenizerErrorToString = e.tokenizerErrorToString;
const TokenizerError = e.TokenizerError;
const TokenizerState = @import("state.zig").TokenizerState;
const testing = std.testing;

pub const ErrorMessage = struct {
    code: []const u8,
    line: usize,

    pub fn format(self: ErrorMessage, writer: anytype) !void {
        try writer.print("ErrorMessage code: {s}, line: {}\n", .{ self.code, self.line });
    }
};

allocator: std.mem.Allocator,
tokens: std.ArrayList(Token),
errors: std.ArrayList(ErrorMessage),

const vtable = Vtable{
    .handleTokenFn = handleToken,
    .handleErrorFn = handleError,
    .adjustCurrentNodeAndNotInHtmlNamespace = adjustCurrentNodeAndNotInHtmlNamespace,
};

pub fn init(alloc: std.mem.Allocator) TestAdapter {
    return .{
        .allocator = alloc,
        .tokens = .empty,
        .errors = .empty,
    };
}

pub fn adapter(self: *TestAdapter) TokenAdapter {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

pub fn deinit(self: *TestAdapter) void {
    for (self.tokens.items) |*tok|
        tok.deinit(self.allocator);

    self.tokens.deinit(self.allocator);
    self.errors.deinit(self.allocator);
}

// Implement TokenAdapter's method.
/// html5lib's expected output represents adjacent character data as one token, 
/// so this test adapter merges consecutive character tokens before comparison. 
pub fn handleToken(ptr: *anyopaque, token: Token) ?TokenizerState {
    const self: *TestAdapter = @ptrCast(@alignCast(ptr));
    var tk = token;
    if (tk == .CharacterToken and self.tokens.items.len != 0) {
        const previous = &self.tokens.items[self.tokens.items.len - 1];
        if (previous.* == .CharacterToken) {
            previous.CharacterToken.append(tk.CharacterToken.slice()) catch unreachable;
            tk.deinit(self.allocator);
            return null;
        }
    }
    self.tokens.append(self.allocator, tk) catch unreachable;
    return null;
}
// Implement TokenAdapter's method.
pub fn handleError(ptr: *anyopaque, err: TokenizerError, cur_line: usize) void {
    const self: *TestAdapter = @ptrCast(@alignCast(ptr));
    self.errors.append(self.allocator, .{ .code = tokenizerErrorToString(err), .line = cur_line }) catch unreachable;
}

// Implement TokenAdapter's method.
pub fn adjustCurrentNodeAndNotInHtmlNamespace(ptr: *anyopaque) bool {
    _ = ptr;
    return false;
}

pub fn expectError(self: *TestAdapter, idx: usize, expected_err: []const u8, cur_line: usize) !void {
    const actual_error = self.errors.items[idx];

    try testing.expectEqualStrings(expected_err, actual_error.code);
    try testing.expectEqual(cur_line, actual_error.line);
}
