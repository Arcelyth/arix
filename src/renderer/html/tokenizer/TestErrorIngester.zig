const TestErrorIngester = @This();

const std = @import("std");
const e = @import("error.zig");
const tokenizerErrorToString = e.tokenizerErrorToString;
const TokenizerError = e.TokenizerError;

pub const ErrorMessage = struct {
    code: []const u8,
    line: usize,
};

allocator: std.mem.Allocator,
errors: std.ArrayList(ErrorMessage),

pub fn init(alloc: std.mem.Allocator) TestErrorIngester {
    return .{
        .allocator = alloc,
        .errors = .empty,
    };
}

pub fn deinit(self: *TestErrorIngester) void {
    self.errors.deinit(self.allocator);
}

// Not sure if ch is needed, may delete in the future.
pub fn handleError(self: *TestErrorIngester, err: TokenizerError, cur_line: usize, ch: u21) void {
    _ = ch;
    self.errors.append(self.allocator, .{.code = tokenizerErrorToString(err), .line = cur_line}) catch unreachable;
}

