//! Iterator for P1: split at B, keeping the separator with the preceding paragraph.
//! https://www.unicode.org/reports/tr9/#P1
const ParagraphIterator = @This();
const BidiCharType = @import("types.zig").BidiCharType;

classes: []const BidiCharType,
position: usize = 0,

/// Half-open indices into the input class slice.
pub const Range = struct { start: usize, end: usize };

/// Returns the next paragraph, or null at the end of the input.
pub fn next(self: *ParagraphIterator) ?Range {
    const start = self.position;
    if (start == self.classes.len) return null;
    while (self.position < self.classes.len) {
        const class = self.classes[self.position];
        self.position += 1;
        if (class == .B) break;
    }

    return .{
        .start = start,
        .end = self.position,
    };
}

test "bidi P1: separators stay with preceding paragraphs" {
    const testing = @import("std").testing;
    var iterator: ParagraphIterator = .{
        .classes = &.{ .B, .L, .S, .WS, .LRI, .R, .B, .PDI, .AL, .B, .B },
    };
    const expected = [_]Range{
        .{ .start = 0, .end = 1 },
        .{ .start = 1, .end = 7 },
        .{ .start = 7, .end = 10 },
        .{ .start = 10, .end = 11 },
    };

    for (expected) |range| try testing.expectEqualDeep(range, iterator.next().?);
    try testing.expectEqual(null, iterator.next());
    try testing.expectEqual(null, iterator.next());
}

test "bidi P1: empty input and text without a separator" {
    const testing = @import("std").testing;
    var empty: ParagraphIterator = .{ .classes = &.{} };
    try testing.expectEqual(null, empty.next());

    var iterator: ParagraphIterator = .{
        .classes = &.{ .AL, .WS, .EN },
    };
    try testing.expectEqualDeep(Range{ .start = 0, .end = 3 }, iterator.next().?);
    try testing.expectEqual(null, iterator.next());
}
