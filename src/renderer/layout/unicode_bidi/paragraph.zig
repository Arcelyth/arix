const BidiCharType = @import("types.zig").BidiCharType;

/// P2–P3: Determine one paragraph's embedding level level from its original bidi classes.
/// A supplied level overrides detection, otherwise skip isolates and use the
/// first strong character: L gives 0, R or AL gives 1, and no match gives 0.
pub fn paragraphLevel(classes: []const BidiCharType, supplied_level: ?u1) u1 {
    if (supplied_level) |level| return level;
    var isolate_depth: usize = 0;
    for (classes) |class| {
        if (class == .B) break;
        if (class.isIsolate()) {
            isolate_depth += 1;
        } else if (class == .PDI) {
            isolate_depth -= @min(isolate_depth, 1);
        } else if (isolate_depth == 0 and class.isStrong()) {
            return if (class == .L) 0 else 1;
        }
    }
    return 0;
}

test "bidi P2-P3: first strong character and supplied base level" {
    const testing = @import("std").testing;
    const Case = struct { classes: []const BidiCharType, expected: u1 };

    const cases = [_]Case{
        .{ .classes = &.{}, .expected = 0 },
        .{ .classes = &.{ .WS, .EN, .AN, .NSM, .ON }, .expected = 0 },
        .{ .classes = &.{ .WS, .L, .AL }, .expected = 0 },
        .{ .classes = &.{ .EN, .R, .L }, .expected = 1 },
        .{ .classes = &.{ .WS, .AL, .L }, .expected = 1 },
        .{ .classes = &.{ .RLO, .L, .PDF }, .expected = 0 },
        .{ .classes = &.{ .LRE, .R, .PDF }, .expected = 1 },
    };
    for (cases) |case| {
        try testing.expectEqual(case.expected, paragraphLevel(case.classes, null));
        try testing.expectEqual(@as(u1, 0), paragraphLevel(case.classes, 0));
        try testing.expectEqual(@as(u1, 1), paragraphLevel(case.classes, 1));
    }
}

test "bidi P2-P3: skip nested and unmatched isolates" {
    const testing = @import("std").testing;

    for ([_]BidiCharType{ .LRI, .RLI, .FSI }) |initiator| {
        try testing.expectEqual(@as(u1, 0), paragraphLevel(&.{ initiator, .R, .PDI, .L }, null));
        try testing.expectEqual(@as(u1, 1), paragraphLevel(&.{ initiator, .L, .PDI, .AL }, null));
        try testing.expectEqual(@as(u1, 0), paragraphLevel(&.{ initiator, .AL }, null));
    }
    try testing.expectEqual(@as(u1, 1), paragraphLevel(&.{ .LRI, .L, .FSI, .R, .PDI, .L, .PDI, .AL }, null));
    try testing.expectEqual(@as(u1, 0), paragraphLevel(&.{ .FSI, .R, .RLI, .L, .PDI, .AL }, null));
    try testing.expectEqual(@as(u1, 1), paragraphLevel(&.{ .PDI, .PDI, .AL }, null));
}

test "bidi P2-P3: detect each P1 paragraph independently" {
    const testing = @import("std").testing;
    const ParagraphIterator = @import("ParagraphIterator.zig");

    const classes = [_]BidiCharType{ .LRI, .AL, .B, .R, .B, .L, .B, .EN };
    var iterator: ParagraphIterator = .{ .classes = &classes };
    for ([_]u1{ 0, 1, 0, 0 }) |expected| {
        const range = iterator.next().?;
        try testing.expectEqual(expected, paragraphLevel(classes[range.start..range.end], null));
    }
    try testing.expectEqual(null, iterator.next());
    try testing.expectEqual(@as(u1, 0), paragraphLevel(&.{ .B, .AL }, null));
}
