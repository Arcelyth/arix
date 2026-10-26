//! Preparations for Implicit Processing
//! https://www.unicode.org/reports/tr9/#Preparations_for_Implicit_Processing
const std = @import("std");
const BidiCharType = @import("defs.zig").BidiCharType;
const defs = @import("defs.zig");
const IsolatingRunSequence = defs.IsolatingRunSequence;
const LevelRun = defs.LevelRun;

/// For example:
///
/// Paragraph text:
/// text1, RLI, text2, PDI, RLI, text3, PDI, text4
///
/// Level runs:
/// - text1, RLI        // level 0
/// - text2             // level 1
/// - PDI, RLI          // level 0
/// - text3             // level 1
/// - PDI, text4        // level 0
///
/// Isolating run sequences:
/// - text1, RLI, PDI, RLI, PDI, text4      // level 0
/// - text2                                 // level 1
/// - text3                                 // level 1
pub fn prepare(
    allocator: std.mem.Allocator,
    original: []const BidiCharType,
    levels: []const u8,
    base: u1,
) ![]IsolatingRunSequence {
    std.debug.assert(original.len == levels.len);

    const indices = try activeIndices(allocator, original);
    defer allocator.free(indices);

    const runs = try levelRuns(allocator, original, indices, levels, base);
    defer allocator.free(runs);
    try linkIsolates(allocator, original, indices, runs);
    return collectSequences(allocator, indices, runs);
}

pub fn deinit(allocator: std.mem.Allocator, sequences: []const IsolatingRunSequence) void {
    for (sequences) |sequence| sequence.deinit(allocator);
    allocator.free(sequences);
}

/// [X9]Filter by original class without deleting or renumbering source characters.
fn activeIndices(allocator: std.mem.Allocator, original: []const BidiCharType) ![]usize {
    var indices: std.ArrayList(usize) = .empty;
    errdefer indices.deinit(allocator);
    for (original, 0..) |class, i| if (!class.isRemoved()) {
        try indices.append(allocator, i);
    };
    return indices.toOwnedSlice(allocator);
}

inline fn direction(level: u8) BidiCharType {
    return if (level & 1 == 0) .L else .R;
}

/// Splits the X9-filtered character sequence into maximal level runs.
/// `base` is the paragraph embedding level, which must be either 0 or 1.
fn levelRuns(
    allocator: std.mem.Allocator,
    original: []const BidiCharType,
    indices: []const usize,
    levels: []const u8,
    base: u1,
) ![]LevelRun {
    var runs: std.ArrayList(LevelRun) = .empty;
    errdefer runs.deinit(allocator);

    var start: usize = 0;
    while (start < indices.len) {
        const level = levels[indices[start]];
        var end = start + 1;
        while (end < indices.len and levels[indices[end]] == level) : (end += 1) {}

        const previous = if (start > 0) levels[indices[start - 1]] else base;
        const following = if (end < indices.len and !original[indices[end - 1]].isIsolate())
            levels[indices[end]]
        else
            base;
        try runs.append(allocator, .{
            .start = start,
            .end = end,
            .level = level,
            .sos = direction(@max(level, previous)),
            .eos = direction(@max(level, following)),
        });
        start = end;
    }
    return runs.toOwnedSlice(allocator);
}

/// Link level runs that belong to the same isolating run sequence.
fn linkIsolates(
    allocator: std.mem.Allocator,
    original: []const BidiCharType,
    indices: []const usize,
    runs: []LevelRun,
) !void {
    const owner = try allocator.alloc(usize, original.len);
    defer allocator.free(owner);

    for (runs, 0..) |run, i| for (indices[run.start..run.end]) |index| {
        owner[index] = i;
    };
    var stack: std.ArrayList(usize) = .empty;
    defer stack.deinit(allocator);

    for (original, 0..) |class, i| {
        if (class.isIsolate()) {
            try stack.append(allocator, i);
        } else if (class == .PDI) {
            const initiator = stack.pop() orelse continue;
            const run = &runs[owner[initiator]];
            if (indices[run.end - 1] != initiator) continue;

            std.debug.assert(run.level == runs[owner[i]].level);

            run.next = owner[i];
            runs[owner[i]].continuation = true;
        }
    }
}

fn collectSequences(allocator: std.mem.Allocator, indices: []const usize, runs: []const LevelRun) ![]IsolatingRunSequence {
    var result: std.ArrayList(IsolatingRunSequence) = .empty;
    errdefer {
        for (result.items) |sequence| sequence.deinit(allocator);
        result.deinit(allocator);
    }
    for (runs, 0..) |run, i| {
        if (run.continuation) continue;
        const sequence = try collectSequence(allocator, indices, runs, i);
        errdefer sequence.deinit(allocator);
        try result.append(allocator, sequence);
    }

    return result.toOwnedSlice(allocator);
}

fn collectSequence(
    allocator: std.mem.Allocator,
    indices: []const usize,
    runs: []const LevelRun,
    first: usize,
) !IsolatingRunSequence {
    var collected: std.ArrayList(usize) = .empty;
    errdefer collected.deinit(allocator);
    var current = first;
    while (true) {
        const run = runs[current];
        try collected.appendSlice(allocator, indices[run.start..run.end]);

        current = run.next orelse return .{
            .indices = try collected.toOwnedSlice(allocator),
            .level = runs[first].level,
            .sos = runs[first].sos,
            .eos = run.eos,
        };
    }
}

test "bidi prepare: simple LTR text" {
    const allocator = std.testing.allocator;
    const result = try prepare(
        allocator,
        &.{ .L, .WS, .L },
        &.{ 0, 0, 0 },
        0,
    );
    defer deinit(allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, result[0].indices);
    try std.testing.expectEqual(@as(u8, 0), result[0].level);
    try std.testing.expectEqual(.L, result[0].sos);
    try std.testing.expectEqual(.L, result[0].eos);
}

test "bidi prepare: skip BN without changing original indices" {
    const allocator = std.testing.allocator;
    const result = try prepare(
        allocator,
        &.{ .L, .BN, .L },
        &.{ 0, 0, 0 },
        0,
    );
    defer deinit(allocator, result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, result[0].indices);
}

test "bidi prepare: isolate separates inner and outer text" {
    const allocator = std.testing.allocator;
    const result = try prepare(
        allocator,
        &.{ .L, .RLI, .R, .PDI, .L },
        &.{ 0, 0, 1, 0, 0 },
        0,
    );
    defer deinit(allocator, result);

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 3, 4 }, result[0].indices);
    try std.testing.expectEqualSlices(usize, &.{2}, result[1].indices);
    try std.testing.expectEqual(@as(u8, 1), result[1].level);
    try std.testing.expectEqual(.R, result[1].sos);
    try std.testing.expectEqual(.R, result[1].eos);
}
