const std = @import("std");

/// Parses an ASCII domain. Unicode IDNA processing is not implemented yet.
/// https://url.spec.whatwg.org/#concept-domain-parser
pub fn parse(allocator: std.mem.Allocator, input: []const u21) ![]u8 {
    _ = allocator;
    _ = input;
    @panic("TODO");
}
