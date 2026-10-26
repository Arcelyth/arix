//! 3.4 Reordering Resolved Levels.
//! https://www.unicode.org/reports/tr9/#Reordering_Resolved_Levels
const std = @import("std");
const defs = @import("defs.zig");
const BidiCharType = defs.BidiCharType;
const EmbeddingLevel = defs.EmbeddingLevel;
const ParagraphLevel = defs.ParagraphLevel;

/// [L1]Resets separators and adjacent or trailing whitespace to the paragraph level.
pub fn resetLevels(original: []const BidiCharType, levels: []EmbeddingLevel, base: ParagraphLevel) void {
    std.debug.assert(original.len == levels.len);

    var start: ?usize = null;
    for (original, 0..) |class, i| {
        if (class.isRemoved()) levels[i] = if (i > 0) levels[i - 1] else base;

        if (class == .S or class == .B) {
            @memset(levels[start orelse i .. i + 1], base);
            start = null;
        } else if (isResetWhitespace(class)) {
            if (start == null) start = i;
        } else {
            start = null;
        }
    }
    if (start) |i| @memset(levels[i..], base);
}

fn isResetWhitespace(class: BidiCharType) bool {
    return class == .WS or class.isIsolate() or class == .PDI or class.isRemoved();
}

/// [L2]Reverses sequences from the highest level down to the lowest odd level.
///
/// For example:
/// Levels:        0, 1, 2, 2, 1, 0
/// Initial order: 0, 1, 2, 3, 4, 5
/// Level 2:       0, 1, 3, 2, 4, 5
/// Level 1:       0, 4, 2, 3, 1, 5
/// Visual order:  0, 4, 2, 3, 1, 5
pub fn visualOrder(levels: []const EmbeddingLevel, order: []usize) void {
    std.debug.assert(levels.len == order.len);
    var highest: EmbeddingLevel = 0;
    var lowest: EmbeddingLevel = std.math.maxInt(EmbeddingLevel);
    for (levels, 0..) |level, i| {
        order[i] = i;
        highest = @max(highest, level);
        lowest = @min(lowest, level);
    }
    const lowest_odd = lowest | 1;
    while (highest >= lowest_odd) : (highest -= 1) {
        reverseSequences(levels, order, highest);
    }
}

/// Reverses each contiguous sequence whose embedding level is
/// greater than or equal to the current L2 level.
fn reverseSequences(levels: []const EmbeddingLevel, order: []usize, level: EmbeddingLevel) void {
    var i: usize = 0;
    while (i < order.len) {
        if (levels[order[i]] < level) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < order.len and levels[order[i]] >= level) : (i += 1) {}
        std.mem.reverse(usize, order[start..i]);
    }
}

test "bidi L1: reset separators and preceding whitespace" {
    const original = [_]BidiCharType{ .R, .WS, .S, .R, .WS, .B };
    var levels = [_]EmbeddingLevel{ 1, 1, 1, 1, 1, 1 };

    resetLevels(&original, &levels, 0);

    try std.testing.expectEqualSlices(EmbeddingLevel, &.{ 1, 0, 0, 1, 0, 0 }, &levels);
}

test "bidi L1: trailing whitespace and isolate controls use RTL paragraph level" {
    const original = [_]BidiCharType{ .L, .WS, .L, .WS, .FSI, .LRI, .RLI, .PDI };
    var levels = [_]EmbeddingLevel{ 2, 2, 2, 2, 2, 2, 2, 2 };

    resetLevels(&original, &levels, 1);

    try std.testing.expectEqualSlices(EmbeddingLevel, &.{ 2, 2, 2, 1, 1, 1, 1, 1 }, &levels);
}

test "bidi L1: retained X9 controls inherit levels and join whitespace" {
    const original = [_]BidiCharType{ .LRE, .R, .PDF, .L, .WS, .BN, .RLO };
    var levels = [_]EmbeddingLevel{ 4, 1, 4, 2, 2, 4, 4 };

    resetLevels(&original, &levels, 0);

    try std.testing.expectEqualSlices(EmbeddingLevel, &.{ 0, 1, 1, 2, 0, 0, 0 }, &levels);
}

test "bidi L1: reset only the supplied line and allow empty lines" {
    const original = [_]BidiCharType{ .R, .WS, .R, .WS };
    var levels = [_]EmbeddingLevel{ 1, 1, 1, 1 };

    resetLevels(original[0..2], levels[0..2], 0);
    resetLevels(original[0..0], levels[0..0], 0);

    try std.testing.expectEqualSlices(EmbeddingLevel, &.{ 1, 0, 1, 1 }, &levels);
}

test "bidi L2: nested levels preserve number order" {
    var order: [6]usize = undefined;

    visualOrder(&.{ 0, 1, 2, 2, 1, 0 }, &order);

    try std.testing.expectEqualSlices(usize, &.{ 0, 4, 2, 3, 1, 5 }, &order);
}

test "bidi L2: reverse through intermediate levels not present in line" {
    var order: [4]usize = undefined;

    visualOrder(&.{ 1, 3, 3, 1 }, &order);

    try std.testing.expectEqualSlices(usize, &.{ 3, 2, 1, 0 }, &order);
}

test "bidi L2: even levels and empty lines" {
    var order: [3]usize = undefined;

    visualOrder(&.{ 2, 2, 2 }, &order);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &order);

    visualOrder(&.{}, order[0..0]);
}
