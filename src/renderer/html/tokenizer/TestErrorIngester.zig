const TestErrorIngester = @This();

const std = @import("std");
const e = @import("error.zig");
const tokenizerErrorToString = e.tokenizerErrorToString;
const TokenizerError = e.TokenizerError;
const testing = std.testing;

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
    self.errors.append(self.allocator, .{ .code = tokenizerErrorToString(err), .line = cur_line }) catch unreachable;
}

pub fn expectError(self: *TestErrorIngester, idx: usize, expected_err: []const u8, cur_line: usize) !void {
    const actual_error = self.errors.items[idx];

    try testing.expectEqualStrings(expected_err, actual_error.code); 
    try testing.expectEqual(cur_line, actual_error.line); 
}
