//! https://url.spec.whatwg.org/#concept-ipv4-parser
const std = @import("std");

pub fn parse(input: []const u8) ![4]u8 {
    _ = input;
    @panic("TODO");
}

pub fn serialize(allocator: std.mem.Allocator, address: [4]u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{d}.{d}.{d}.{d}",
        .{ address[0], address[1], address[2], address[3] },
    );
}
