const BidiInfo = @This();
const std = @import("std");
const defs = @import("defs.zig");
const ParagraphIterator = @import("ParagraphIterator.zig");
const paragraph = @import("paragraph.zig");
const explicit = @import("explicit.zig");
const prepare = @import("prepare.zig");
const weak = @import("weak.zig");
const neutral = @import("neutral.zig");
const implicit = @import("implicit.zig");
const reorder = @import("reorder.zig");
const Range = ParagraphIterator.Range;

/// Stores the resolved bidirectional information for a text.
pub const ParagraphInfo = struct {
    /// Half-open code point range, including the paragraph separator when present.
    range: Range,
    /// The resolved paragraph embedding level.
    level: defs.ParagraphLevel,
};

/// Original bidi character types, preserved for later processing stages.
original_classes: []defs.BidiCharType,
/// Resolved embedding level for each code point.
levels: []defs.EmbeddingLevel,
paragraphs: []ParagraphInfo,

pub fn init(
    allocator: std.mem.Allocator,
    text: []const u21,
    supplied_level: ?defs.ParagraphLevel,
) !BidiInfo {
    const classes = try allocator.alloc(defs.BidiCharType, text.len);
    errdefer allocator.free(classes);
    for (text, classes) |codepoint, *class|
        class.* = defs.bidiClass(codepoint);
    const paragraphs = try collectParagraphs(allocator, classes, supplied_level);
    errdefer allocator.free(paragraphs);
    const levels = try allocator.alloc(defs.EmbeddingLevel, text.len);
    errdefer allocator.free(levels);
    // Buffer for bidi types that are modified during resolution.
    const processing = try allocator.alloc(defs.BidiCharType, text.len);
    defer allocator.free(processing);

    for (paragraphs) |para| {
        const range = para.range;
        try computeParagraph(
            allocator,
            text[range.start..range.end],
            classes[range.start..range.end],
            para.level,
            levels[range.start..range.end],
            processing[range.start..range.end],
        );
    }

    return .{
        .original_classes = classes,
        .levels = levels,
        .paragraphs = paragraphs,
    };
}

pub fn deinit(self: BidiInfo, allocator: std.mem.Allocator) void {
    allocator.free(self.original_classes);
    allocator.free(self.levels);
    allocator.free(self.paragraphs);
}

/// Applies L1 only within the supplied line.
/// Pass the returned line slice to reorder.visualOrder for L2.
pub fn reorderedLevels(self: BidiInfo, allocator: std.mem.Allocator, para: ParagraphInfo, line: Range) ![]defs.EmbeddingLevel {
    std.debug.assert(para.range.start <= line.start and line.start <= line.end);
    std.debug.assert(line.end <= para.range.end and para.range.end <= self.levels.len);

    const levels = try allocator.dupe(defs.EmbeddingLevel, self.levels);
    reorder.resetLevels(
        self.original_classes[line.start..line.end],
        levels[line.start..line.end],
        para.level,
    );
    return levels;
}

fn collectParagraphs(allocator: std.mem.Allocator, original: []const defs.BidiCharType, supplied_level: ?defs.ParagraphLevel) ![]ParagraphInfo {
    var paragraphs: std.ArrayList(ParagraphInfo) = .empty;
    errdefer paragraphs.deinit(allocator);
    var iterator: ParagraphIterator = .{ .classes = original };
    while (iterator.next()) |range| {
        try paragraphs.append(allocator, .{
            .range = range,
            .level = paragraph.paragraphLevel(original[range.start..range.end], supplied_level),
        });
    }
    return paragraphs.toOwnedSlice(allocator);
}

fn computeParagraph(
    allocator: std.mem.Allocator,
    text: []const u21,
    original: []const defs.BidiCharType,
    base: defs.ParagraphLevel,
    levels: []defs.EmbeddingLevel,
    processing: []defs.BidiCharType,
) !void {
    try explicit.resolve(allocator, original, base, levels, processing);
    const sequences = try prepare.prepare(allocator, original, levels, base);
    defer prepare.deinit(allocator, sequences);

    for (sequences) |sequence| {
        weak.resolve(sequence, processing);
        try neutral.resolve(allocator, sequence, text, original, processing);
        implicit.resolve(sequence, processing, levels);
    }
    assignRemovedLevels(original, levels, base);
}

/// Assigns embedding levels to characters excluded from subsequent
/// bidi resolution by UAX #9 X9, preserving the original text indices.
fn assignRemovedLevels(original: []const defs.BidiCharType, levels: []defs.EmbeddingLevel, base: defs.ParagraphLevel) void {
    var previous: defs.EmbeddingLevel = base;
    for (original, levels) |class, *level| {
        if (class.isRemoved()) level.* = previous;
        previous = level.*;
    }
}

test "bidi info: paragraph analysis through line visual order" {
    const allocator = std.testing.allocator;
    // LTR paragraph with an Arabic isolate, then a Hebrew RTL paragraph.
    const text = [_]u21{ 'a', 0x2067, '(', 0x0627, ')', ' ', '1', ' ', 0x2069, '\n', 0x05d0, ' ', '1' };
    const info = try init(allocator, &text, null);
    defer info.deinit(allocator);

    // P1–P3: each paragraph detects its own direction.
    try std.testing.expectEqualDeep(&[_]ParagraphInfo{
        .{
            .range = .{ .start = 0, .end = 10 },
            .level = 0,
        },
        .{
            .range = .{ .start = 10, .end = 13 },
            .level = 1,
        },
    }, info.paragraphs);
    // X1–I2: resolve the isolate, brackets, Arabic number context and implicit levels.
    const expected = [_]defs.EmbeddingLevel{ 0, 0, 1, 1, 1, 1, 2, 1, 0, 0, 1, 1, 2 };
    try std.testing.expectEqualSlices(defs.EmbeddingLevel, &expected, info.levels);

    // Treat each paragraph as one completed line.
    const first = info.paragraphs[0];
    const first_lvs = try info.reorderedLevels(allocator, first, first.range);
    defer allocator.free(first_lvs);
    // L1 resets the trailing space, PDI and paragraph separator to level 0.
    try std.testing.expectEqualSlices(defs.EmbeddingLevel, &.{ 0, 0, 1, 1, 1, 1, 2, 0, 0, 0, 1, 1, 2 }, first_lvs);
    var first_order: [10]usize = undefined;
    reorder.visualOrder(first_lvs[first.range.start..first.range.end], &first_order);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 6, 5, 4, 3, 2, 7, 8, 9 }, &first_order);

    const second = info.paragraphs[1];
    const second_lvs = try info.reorderedLevels(allocator, second, second.range);
    defer allocator.free(second_lvs);
    var second_order: [3]usize = undefined;
    reorder.visualOrder(second_lvs[second.range.start..second.range.end], &second_order);

    try std.testing.expectEqualSlices(usize, &.{ 2, 1, 0 }, &second_order);
    // L2 indices are relative to the line; add its start to read logical text.
    var visual: [3]u21 = undefined;
    for (second_order, 0..) |index, i| visual[i] = text[second.range.start + index];
    try std.testing.expectEqualSlices(u21, &.{ '1', ' ', 0x05d0 }, &visual);

    // Line processing leaves the stored paragraph levels unchanged.
    try std.testing.expectEqualSlices(defs.EmbeddingLevel, &expected, info.levels);
}
