const std = @import("std");
const host = @import("host.zig");

// FIXME: IDNA TODO;
/// Parses an ASCII domain.
/// https://url.spec.whatwg.org/#concept-domain-parser
pub fn parse(allocator: std.mem.Allocator, input: []const u21) ![]u8 {
    const output = try allocator.alloc(u8, input.len);
    errdefer allocator.free(output);
    for (input, output) |cp, *byte| {
        if (cp == 0xFFFD) return error.InvalidHost;
        if (cp >= 0x80) return error.UnsupportedIdna;
        if (cp <= 0x20 or cp == 0x7F or cp == '%' or host.isForbiddenCodePoint(cp))
            return error.InvalidHost;
        byte.* = std.ascii.toLower(@intCast(cp));
    }
    var labels = std.mem.splitScalar(u8, output, '.');
    while (labels.next()) |label|
        if (std.mem.startsWith(u8, label, "xn--"))
            return error.UnsupportedIdna;
    return output;
}

test "network url domain: parse ASCII domain" {
    const allocator = std.testing.allocator;
    const domain = try parse(allocator, &.{ 'E', 'X', '.', 'o', 'r', 'g' });
    defer allocator.free(domain);
    try std.testing.expectEqualStrings("ex.org", domain);
    try std.testing.expectError(error.InvalidHost, parse(allocator, &.{ 'a', '#', 'b' }));
    try std.testing.expectError(error.InvalidHost, parse(allocator, &.{0xFFFD}));
}
