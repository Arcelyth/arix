//! 3.3.6 Resolving Implicit Levels.
//! https://www.unicode.org/reports/tr9/#Resolving_Implicit_Levels
const std = @import("std");
const defs = @import("defs.zig");
const BidiCharType = defs.BidiCharType;
const EmbeddingLevel = defs.EmbeddingLevel;
const IsolatingRunSequence = defs.IsolatingRunSequence;

/// Applies I1–I2 to one isolating run sequence.
pub fn resolve(sequence: IsolatingRunSequence, processing: []const BidiCharType, levels: []EmbeddingLevel) void {
    std.debug.assert(processing.len == levels.len);

    for (sequence.indices) |index| {
        const level = &levels[index];
        if (defs.embeddingDirection(level.*) == .L) {
            // I1.
            level.* += switch (processing[index]) {
                .R => 1,
                .EN, .AN => 2,
                else => 0,
            };
        } else {
            // I2.
            level.* += switch (processing[index]) {
                .L, .EN, .AN => 1,
                else => 0,
            };
        }
    }
}

test "bidi implicit I1: even levels" {
    var indices = [_]usize{ 0, 1, 2, 3 };
    var levels = [_]EmbeddingLevel{ 0, 0, 0, 0 };
    const sequence: IsolatingRunSequence = .{
        .indices = &indices,
        .level = 0,
        .sos = .L,
        .eos = .L,
    };

    resolve(sequence, &.{ .L, .R, .EN, .AN }, &levels);

    try std.testing.expectEqualSlices(EmbeddingLevel, &.{ 0, 1, 2, 2 }, &levels);
}

test "bidi implicit I2: odd levels" {
    var indices = [_]usize{ 0, 1, 2, 3 };
    var levels = [_]EmbeddingLevel{ 1, 1, 1, 1 };
    const sequence: IsolatingRunSequence = .{
        .indices = &indices,
        .level = 1,
        .sos = .R,
        .eos = .R,
    };

    resolve(sequence, &.{ .L, .R, .EN, .AN }, &levels);

    try std.testing.expectEqualSlices(EmbeddingLevel, &.{ 2, 1, 2, 2 }, &levels);
}

test "bidi implicit: reach maximum implicit level and skip other indices" {
    var indices = [_]usize{ 0, 2 };
    var levels = [_]EmbeddingLevel{ defs.max_depth, 0, defs.max_depth };
    const sequence: IsolatingRunSequence = .{
        .indices = &indices,
        .level = defs.max_depth,
        .sos = .R,
        .eos = .R,
    };

    resolve(sequence, &.{ .L, .BN, .AN }, &levels);

    try std.testing.expectEqualSlices(EmbeddingLevel, &.{ defs.max_depth + 1, 0, defs.max_depth + 1 }, &levels);
}
