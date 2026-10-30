const Input = @This();
const std = @import("std");
const ascii = @import("../../utils/ascii.zig");

chars: std.unicode.Utf8Iterator = .{ .bytes = "", .i = 0 },

/// Input must be valid UTF-8. Boundary controls and spaces are kept.
pub fn initNoTrim(input: []const u8) Input {
    return .{
        .chars = .{ .bytes = input, .i = 0 },
    };
}

/// Trims boundary tabs and newlines.
pub fn initTrimTabAndNewlines(input: []const u8) Input {
    return initTrim(input, isTabOrNewline);
}

/// Trims boundary C0 controls and spaces.
pub fn initTrimC0ControlAndSpace(input: []const u8) Input {
    return initTrim(input, isC0OrSpace);
}

fn initTrim(input: []const u8, comptime predicate: fn (u8) bool) Input {
    var start: usize = 0;
    var end = input.len;
    while (start < end and predicate(input[start])) : (start += 1) {}
    while (end > start and predicate(input[end - 1])) : (end -= 1) {}

    return initNoTrim(input[start..end]);
}

/// Remaining UTF-8 bytes, including tabs and newlines.
pub fn asSlice(self: *const Input) []const u8 {
    return self.chars.bytes[self.chars.i..];
}

fn isTabOrNewline(byte: u8) bool {
    return ascii.isAsciiTabOrNewline(u8, byte);
}

fn isC0OrSpace(byte: u8) bool {
    return ascii.isC0OrSpace(u8, byte);
}

/// Returns the next code point, skipping tabs and newlines.
pub fn next(self: *Input) ?u21 {
    while (self.chars.nextCodepoint()) |cp| {
        if (!ascii.isAsciiTabOrNewline(u21, cp)) return cp;
    }
    return null;
}

/// Returns a code point and its original UTF-8 bytes.
pub fn nextUtf8(self: *Input) ?struct { codepoint: u21, bytes: []const u8 } {
    while (self.chars.nextCodepointSlice()) |bytes| {
        const cp = std.unicode.utf8Decode(bytes) catch unreachable;
        if (!ascii.isAsciiTabOrNewline(u21, cp))
            return .{ .codepoint = cp, .bytes = bytes };
    }
    return null;
}

pub fn isEmpty(self: *const Input) bool {
    var remaining = self.*;
    return remaining.next() == null;
}

/// Checks a UTF-8 prefix without consuming input.
pub fn startsWith(self: *const Input, prefix: []const u8) bool {
    return self.splitPrefix(prefix) != null;
}

/// Returns the input after a matching UTF-8 prefix, or null.
pub fn splitPrefix(self: *const Input, prefix: []const u8) ?Input {
    var expected = std.unicode.Utf8Iterator{ .bytes = prefix, .i = 0 };
    var remaining = self.*;
    while (expected.nextCodepoint()) |cp| {
        if (remaining.next() != cp) return null;
    }
    return remaining;
}

/// Returns the first code point and the input after it.
pub fn splitFirst(self: *const Input) struct {
    codepoint: ?u21,
    remaining: Input,
} {
    var remaining = self.*;
    const cp = remaining.next();

    return .{
        .codepoint = cp,
        .remaining = remaining,
    };
}

/// Counts matching code points and returns the input after them.
pub fn countMatching(self: *const Input, comptime predicate: anytype) struct {
    count: usize,
    remaining: Input,
} {
    var count: usize = 0;
    var remaining = self.*;
    while (true) {
        var candidate = remaining;
        const cp = candidate.next() orelse break;
        if (!predicate(cp)) break;
        remaining = candidate;
        count += 1;
    }
    return .{
        .count = count,
        .remaining = remaining,
    };
}

test "network url input: filtered iteration and prefix checks" {
    const testing = std.testing;
    var input = Input.initNoTrim("\th\nt\rtps://例え.test\r");
    try testing.expect(input.startsWith("https://例え"));
    try testing.expect(!input.startsWith("http:"));
    try testing.expectEqual(@as(usize, 0), input.chars.i);

    var remaining = input.splitPrefix("https://").?;
    const char = remaining.nextUtf8().?;
    try testing.expectEqual(@as(u21, '例'), char.codepoint);
    try testing.expectEqualStrings("例", char.bytes);
    try testing.expect(char.bytes.ptr == input.chars.bytes.ptr + 11);
    const first = remaining.splitFirst();
    try testing.expectEqual(@as(?u21, 'え'), first.codepoint);
    var after_first = first.remaining;
    try testing.expectEqual(@as(?u21, '.'), after_first.next());
    try testing.expectEqual(@as(?u21, 'え'), remaining.next());

    var digits = Input.initNoTrim("1\t23x");
    const matched = digits.countMatching(ascii.isAsciiDigit);
    try testing.expectEqual(@as(usize, 3), matched.count);
    var suffix = matched.remaining;
    try testing.expectEqual(@as(?u21, 'x'), suffix.next());
    try testing.expect(suffix.isEmpty());
    try testing.expectEqual(@as(?u21, '1'), digits.next());

    var empty = Input.initNoTrim("\t\n\r");
    try testing.expect(empty.isEmpty());
    try testing.expect(empty.next() == null);
    try testing.expect(empty.nextUtf8() == null);
    try testing.expect(empty.splitFirst().codepoint == null);
    try testing.expect(empty.startsWith(""));
    var tabs = Input.initTrimTabAndNewlines("\t a \n");
    try testing.expectEqual(@as(?u21, ' '), tabs.next());
    var controls = Input.initTrimC0ControlAndSpace("\x00\x1f a \x0b\x0c");
    try testing.expectEqual(@as(?u21, 'a'), controls.next());
    try testing.expect(controls.isEmpty());
}
