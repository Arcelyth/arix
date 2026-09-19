const Decoder = @This();
const std = @import("std");
const Encoding = @import("encoding.zig").Encoding;

pub const ErrorMode = enum { replacement, fatal };

encoding: Encoding,

/// https://encoding.spec.whatwg.org/#concept-encoding-process
pub fn processQueue(self: *Decoder, allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) []u21 {
    // TODO: Encoding §4.1
    _ = self;
    _ = allocator;
    _ = input;
    _ = mode;
}
