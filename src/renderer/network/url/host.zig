const std = @import("std");
const encoding = @import("../../encoding/encoding.zig");
const percent = @import("percent_encoded.zig");
const ascii = @import("../../utils/ascii.zig");
const domains = @import("domain.zig");
const ipv4 = @import("ipv4.zig");
const ipv6 = @import("ipv6.zig");
const ErrorAdapter = @import("ErrorAdapter.zig");

/// Parses and serializes a host. Unicode IDNA processing is not implemented yet.
/// https://url.spec.whatwg.org/#concept-host-parser
pub fn parse(
    allocator: std.mem.Allocator,
    input: []const u8,
    is_opaque: bool,
    adapter: ?ErrorAdapter,
) ![]const u8 {
    if (std.mem.startsWith(u8, input, "[")) {
        if (!std.mem.endsWith(u8, input, "]")) {
            if (adapter) |value| value.handleError(.IPv6Unclosed);
            return error.IPv6Unclosed;
        }
        return ipv6.serialize(allocator, try ipv6.parse(input[1 .. input.len - 1]));
    }
    if (is_opaque) return parseOpaque(allocator, input);
    const bytes = try percent.decode(allocator, input);
    errdefer allocator.free(bytes);
    const codepoints = try encoding.utf8DecodeWithoutBom(allocator, bytes);
    defer allocator.free(codepoints);
    const domain = try domains.parse(allocator, codepoints);
    errdefer allocator.free(domain);

    if (endsInNumber(domain)) {
        const address = try ipv4.parse(domain);
        const output = try ipv4.serialize(allocator, address);
        allocator.free(domain);
        return output;
    }
    return domain;
}

/// Parses and percent-encodes an opaque host.
/// https://url.spec.whatwg.org/#concept-opaque-host-parser
pub fn parseOpaque(allocator: std.mem.Allocator, input: []const u8, adapter: ?ErrorAdapter) ![]const u8 {
    var chars = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (chars.nextCodepoint()) |cp| {
        if (isForbiddenCodePoint(cp)) {
            if (adapter) |value| value.handleError(.HostInvalidCodePoint);
            return error.HostInvalidCodePoint;
        }
    }
    chars.i = 0;
    while (chars.nextCodepoint()) |cp| {
        if (cp != '%' and !isUrlCodePoint(cp)) {
            if (adapter) |value| value.handleError(.InvalidUrlUnit);
            break;
        }
    }
    for (input, 0..) |byte, i| {
        if (byte == '%' and (input.len - i < 3 or
            !ascii.isAsciiHexDigit(input[i + 1]) or !ascii.isAsciiHexDigit(input[i + 2])))
        {
            if (adapter) |value| value.handleError(.InvalidUrlUnit);
            break;
        }
    }

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    chars.i = 0;
    while (chars.nextCodepoint()) |cp| try percent.append(allocator, &output, cp, .c0_control);
    return output.toOwnedSlice(allocator);
}

/// https://url.spec.whatwg.org/#forbidden-host-code-point
pub inline fn isForbiddenCodePoint(byte: u8) bool {
    return switch (byte) {
        0, '\t', '\n', '\r', ' ', '#', '/', ':', '<', '>', '?', '@', '[', '\\', ']', '^', '|' => true,
        else => false,
    };
}

/// https://url.spec.whatwg.org/#url-code-points
pub fn isUrlCodePoint(cp: u21) bool {
    if (ascii.isAsciiAlphanum(cp)) return true;
    if (cp >= 0xa0 and
        cp <= 0x10fffd and
        !ascii.isSurrogate(u21, cp) and
        !ascii.isNoncharacter(u21, cp))
        return true;
    return switch (cp) {
        '!', '$', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '=', '?', '@', '_', '~' => true,
        else => false,
    };
}

/// https://url.spec.whatwg.org/#ends-in-a-number-checker
pub fn endsInNumber(input: []const u8) bool {
    _ = input;
    @panic("TODO");
}

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
