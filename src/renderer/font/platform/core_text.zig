pub const Font = @import("core_text/Font.zig");
pub const Family = @import("core_text/Family.zig");
pub const shape = @import("core_text/shaping.zig").shape;
const std = @import("std");
const core = @import("core_foundation_zig");
const cf = core.core_foundation;

/// Returns Unicode line-breaking opportunities as UTF-8 byte offsets.
pub fn lineBreaks(allocator: std.mem.Allocator, text: []const u8) ![]usize {
    const string = try cf.CFString.init(text);
    defer string.deinit();
    const tokenizer = try cf.CFStringTokenizer.init(string, core.raw.kCFStringTokenizerUnitLineBreak);
    defer tokenizer.deinit();
    var result: std.ArrayList(usize) = .empty;
    errdefer result.deinit(allocator);

    var iterator = std.unicode.Utf8View.initUnchecked(text).iterator();
    var units: usize = 0;
    while (tokenizer.advanceToNextToken() != core.raw.kCFStringTokenizerTokenNone) {
        const range = tokenizer.getCurrentTokenRange();
        const end = cf.CFIndex.toUsize(range.location + range.length) orelse return error.InvalidStringIndex;
        while (units < end) {
            const bytes = iterator.nextCodepointSlice() orelse return error.InvalidStringIndex;
            units += if (bytes.len == 4) @as(usize, 2) else 1;
        }
        try result.append(allocator, iterator.i);
    }
    return result.toOwnedSlice(allocator);
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "core_text lineBreaks: UTF-8 byte offsets" {
    const allocator = std.testing.allocator;
    const breaks = try lineBreaks(allocator, "😀 😀");
    defer allocator.free(breaks);

    try std.testing.expectEqualSlices(usize, &.{ 5, 9 }, breaks);
}
