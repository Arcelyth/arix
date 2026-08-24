const TestCase = @This();

const std = @import("std");

data: []const u8,
expected: []const u8,

errors: usize = 0,
fragment: ?[]const u8 = null,
scripting: ?bool = null,

pub fn init() TestCase {
    return .{
        .data = "",
        .expected = "",
        .errors = 0,
        .fragment = null,
        .scripting = null,
    };
}
