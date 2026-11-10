//! HTTP header names and values.
const std = @import("std");

/// A header's name and value are byte sequences, not UTF-8 strings.
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Checks the HTTP field-name token grammar.
/// https://httpwg.org/specs/rfc9110.html#tokens
pub fn isValidName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |byte| {
        switch (byte) {
            '0'...'9', 'A'...'Z', 'a'...'z', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => {},
            else => return false,
        }
    }
    return true;
}

/// Rejects edge spaces or tabs, NUL, CR, and LF.
pub fn isValidValue(value: []const u8) bool {
    if (value.len == 0) return true;
    if (isTabOrSpace(value[0]) or isTabOrSpace(value[value.len - 1])) return false;
    return std.mem.indexOfAny(u8, value, "\x00\r\n") == null;
}

/// Removes HTTP whitespace from both ends.
/// https://fetch.spec.whatwg.org/#concept-header-value-normalize
pub fn normalize(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, "\t\n\r ");
}

/// Reports which part of a header is invalid. Normalize values before calling if needed.
pub fn validate(name: []const u8, value: []const u8) error{ InvalidHeaderName, InvalidHeaderValue }!void {
    if (!isValidName(name)) return error.InvalidHeaderName;
    if (!isValidValue(value)) return error.InvalidHeaderValue;
}

/// Decodes bytes isomorphically and splits at commas outside quoted strings.
/// https://fetch.spec.whatwg.org/#header-value-get-decode-and-split
pub fn getDecodeAndSplit(allocator: std.mem.Allocator, value: []const u8) ![][]u8 {
    var values: std.ArrayList([]u8) = .empty;
    errdefer {
        for (values.items) |item| allocator.free(item);
        values.deinit(allocator);
    }
    var position: usize = 0;
    var start: usize = 0;
    while (true) {
        while (position < value.len and value[position] != '"' and value[position] != ',') : (position += 1) {}
        if (position < value.len and value[position] == '"') {
            collectQuotedString(value, &position);
            if (position < value.len) continue;
        }
        const item = try isomorphicDecode(allocator, std.mem.trim(u8, value[start..position], "\t "));
        errdefer allocator.free(item);
        try values.append(allocator, item);
        if (position == value.len) break;
        position += 1;
        start = position;
    }
    return values.toOwnedSlice(allocator);
}

// Consumes an HTTP quoted string, including its quotes and escaped characters.
// https://fetch.spec.whatwg.org/#collect-an-http-quoted-string
fn collectQuotedString(input: []const u8, position: *usize) void {
    std.debug.assert(input[position.*] == '"');
    position.* += 1;
    while (position.* < input.len) {
        const byte = input[position.*];
        position.* += 1;
        switch (byte) {
            '"' => return,
            '\\' => if (position.* < input.len) {
                position.* += 1;
            },
            else => {},
        }
    }
}

// Each byte becomes the code point with the same value.
fn isomorphicDecode(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var length = bytes.len;
    for (bytes) |byte| if (byte >= 0x80) {
        length += 1;
    };
    const text = try allocator.alloc(u8, length);
    var position: usize = 0;
    for (bytes) |byte| {
        position += std.unicode.utf8Encode(byte, text[position..]) catch unreachable;
    }
    return text;
}

fn isTabOrSpace(byte: u8) bool {
    return byte == '\t' or byte == ' ';
}

test "network headers: name validation and value normalization" {
    try std.testing.expect(isValidName("X-Token!#$%&'*+-.^_`|~0123"));
    try std.testing.expect(!isValidName(""));
    try std.testing.expect(!isValidName("Content Type"));
    try std.testing.expect(!isValidName("name:"));
    try std.testing.expect(!isValidName("\xff"));
    try std.testing.expectEqualStrings("value", normalize(" \t\r\nvalue\n\r\t "));
    try std.testing.expectEqualStrings("\x0b\x0cvalue\x0c", normalize("\x0b\x0cvalue\x0c"));
    try std.testing.expect(isValidValue(""));
    for (0..256) |i| {
        const byte: u8 = @intCast(i);
        const value = [_]u8{ 'x', byte, 'x' };
        try std.testing.expectEqual(byte != 0 and byte != '\r' and byte != '\n', isValidValue(&value));
    }
    try std.testing.expectError(error.InvalidHeaderName, validate("bad name", "value"));
    try std.testing.expectError(error.InvalidHeaderValue, validate("name", " value"));
}

test "network headers: split quoted and empty values" {
    const allocator = std.testing.allocator;
    const Case = struct { input: []const u8, expected: []const []const u8 };
    const cases = [_]Case{
        .{ .input = "nosniff,", .expected = &.{ "nosniff", "" } },
        .{ .input = "", .expected = &.{""} },
        .{ .input = "text/html;\", x/x", .expected = &.{"text/html;\", x/x"} },
        .{ .input = "x/x;test=\"hi\",y/y", .expected = &.{ "x/x;test=\"hi\"", "y/y" } },
        .{ .input = "x / x,,,1", .expected = &.{ "x / x", "", "", "1" } },
        .{ .input = " \"1,2\", 3\t", .expected = &.{ "\"1,2\"", "3" } },
        .{ .input = "\"a\\\",b\", c", .expected = &.{ "\"a\\\",b\"", "c" } },
        .{ .input = "\"end\\", .expected = &.{"\"end\\"} },
        .{ .input = "\xff", .expected = &.{"ÿ"} },
    };
    for (cases) |case| {
        const values = try getDecodeAndSplit(allocator, case.input);
        defer {
            for (values) |value| allocator.free(value);
            allocator.free(values);
        }
        try std.testing.expectEqual(case.expected.len, values.len);
        for (case.expected, values) |expected, actual|
            try std.testing.expectEqualStrings(expected, actual);
    }
}
