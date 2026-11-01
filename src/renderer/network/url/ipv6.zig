//! https://url.spec.whatwg.org/#concept-ipv6-serializer
const std = @import("std");

pub fn parse(input: []const u8) ![16]u8 {
    _ = input;
    @panic("TODO");
}

pub fn serialize(allocator: std.mem.Allocator, address: [16]u8) ![]u8 {
    _ = allocator;
    _ = address;
    @panic("TODO");
}
