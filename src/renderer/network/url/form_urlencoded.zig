//! https://url.spec.whatwg.org/#application/x-www-form-urlencoded
const std = @import("std");
const percent = @import("percent_encoded.zig");
const encoding = @import("../../encoding/encoding.zig");

pub const Pair = struct {
    name: []const u8,
    value: []const u8,

    pub fn deinit(self: Pair, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

/// Parses form data into name-value pairs.
/// https://url.spec.whatwg.org/#concept-urlencoded-parser
pub fn parse(allocator: std.mem.Allocator, input: []const u8) ![]Pair {
    var pairs: std.ArrayList(Pair) = .empty;
    errdefer {
        for (pairs.items) |pair| pair.deinit(allocator);
        pairs.deinit(allocator);
    }
    var sequences = std.mem.splitScalar(u8, input, '&');
    while (sequences.next()) |bytes| {
        if (bytes.len == 0) continue;
        const equals = std.mem.indexOfScalar(u8, bytes, '=');
        const name = try decode(allocator, bytes[0 .. equals orelse bytes.len]);
        errdefer allocator.free(name);
        const value = try decode(allocator, if (equals) |i| bytes[i + 1 ..] else "");
        errdefer allocator.free(value);
        try pairs.append(allocator, .{ .name = name, .value = value });
    }
    return pairs.toOwnedSlice(allocator);
}

/// Serializes name-value pairs as form data.
/// Free the result with allocator.free.
/// https://url.spec.whatwg.org/#concept-urlencoded-serializer
pub fn serialize(allocator: std.mem.Allocator, pairs: []const Pair, enc: encoding.Encoding) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    const output_encoding = encoding.getOutputEncoding(enc);
    for (pairs, 0..) |pair, i| {
        if (i != 0) try output.append(allocator, '&');
        try percent.percentEncodeAfterEncoding(allocator, &output, pair.name, output_encoding, .form_urlencoded);
        try output.append(allocator, '=');
        try percent.percentEncodeAfterEncoding(allocator, &output, pair.value, output_encoding, .form_urlencoded);
    }
    return output.toOwnedSlice(allocator);
}

// Replaces plus signs, percent-decodes, then decodes UTF-8 without stripping a BOM.
fn decode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const bytes = try allocator.dupe(u8, input);
    defer allocator.free(bytes);
    for (bytes) |*byte| if (byte.* == '+') {
        byte.* = ' ';
    };
    const decoded = try percent.decode(allocator, bytes);
    defer allocator.free(decoded);
    const codepoints = try encoding.utf8DecodeWithoutBom(allocator, decoded);
    defer allocator.free(codepoints);

    return encoding.utf8Encode(allocator, codepoints);
}

test "network url form_urlencoded: parse and serialize" {
    const allocator = std.testing.allocator;
    const input = "name=hello+world&tag=%C3%A9%2B";
    const pairs = try parse(allocator, input);
    defer {
        for (pairs) |pair| pair.deinit(allocator);
        allocator.free(pairs);
    }

    try std.testing.expectEqual(@as(usize, 2), pairs.len);
    try std.testing.expectEqualStrings("name", pairs[0].name);
    try std.testing.expectEqualStrings("hello world", pairs[0].value);
    try std.testing.expectEqualStrings("tag", pairs[1].name);
    try std.testing.expectEqualStrings("é+", pairs[1].value);

    const output = try serialize(allocator, pairs, .utf8);
    defer allocator.free(output);
    try std.testing.expectEqualStrings(input, output);
}
