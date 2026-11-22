//! The CSS namespace.
const std = @import("std");
const serialize = @import("serialize.zig");

/// Escapes a UTF-8 string for use as a CSS identifier. Free the result with allocator.free.
/// https://drafts.csswg.org/cssom/#dom-css-escape
pub fn escape(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try serialize.identifier(&output.writer, text);
    return output.toOwnedSlice();
}

test "CSSOM escape identifier" {
    const testing = std.testing;
    for ([_][2][]const u8{
        .{ "", "" },
        .{ "-", "\\-" },
        .{ "-1a", "-\\31 a" },
        .{ "0a", "\\30 a" },
        .{ "--2", "--2" },
        .{ "é×.\x00\x7f", "é\\×\\.�\\7f " },
    }) |case| {
        const escaped = try escape(testing.allocator, case[0]);
        defer testing.allocator.free(escaped);
        try testing.expectEqualStrings(case[1], escaped);
    }
}
