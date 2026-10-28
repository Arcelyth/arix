const std = @import("std");

pub const Host = union(enum) {
    domain: []const u8,
    ipv4: [4]u8,
    ipv6: [16]u8,

    pub fn fromSlice(text: []const u8, is_not_special: bool) Host {
        if (std.mem.startsWith(u8, text, "[")) {
            std.debug.assert(std.mem.endsWith(u8, text, "]"));
            const address = std.Io.net.Ip6Address.parse(text[1 .. text.len - 1], 0) catch unreachable;
            return .{ .ipv6 = address.bytes };
        }
        if (is_not_special) return .{ .domain = text };
        const address = std.Io.net.Ip4Address.parse(text, 0) catch return .{ .domain = text };
        return .{ .ipv4 = address.bytes };
    }
};

test "network url host: from ipv4, ipv6, domain and empty slice" {
    try std.testing.expectEqualStrings("example.org", Host.fromSlice("example.org", false).domain);
    try std.testing.expectEqual([4]u8{ 127, 0, 0, 1 }, Host.fromSlice("127.0.0.1", false).ipv4);
    try std.testing.expectEqualStrings("127.0.0.1", Host.fromSlice("127.0.0.1", true).domain);
    const loopback: [16]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 };
    try std.testing.expectEqual(loopback, Host.fromSlice("[::1]", false).ipv6);
    try std.testing.expectEqualStrings("", Host.fromSlice("", false).domain);
}
