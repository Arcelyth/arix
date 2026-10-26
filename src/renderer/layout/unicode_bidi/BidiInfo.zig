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
    original: []const defs.BidiCharType,
    supplied_level: ?defs.ParagraphLevel,
) !BidiInfo {
    std.debug.assert(text.len == original.len);
    const classes = try allocator.dupe(defs.BidiCharType, original);
    errdefer allocator.free(classes);
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
