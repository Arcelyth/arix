//! 3.3.5 Resolving Neutral and Isolate Formatting Types.
//! https://www.unicode.org/reports/tr9/#Resolving_Neutral_Types
const std = @import("std");
const defs = @import("defs.zig");
const BidiCharType = defs.BidiCharType;
const IsolatingRunSequence = defs.IsolatingRunSequence;

/// Applies N0–N2 to one isolating run sequence.
///
/// For example:
///
/// Isolating run sequence (level 0, LTR):
/// a, (, b, space, c, ), space, א
///
/// Types after W1–W7:
/// L, ON, L, WS, L, ON, WS, R
///
/// After N0:
/// L, L, L, WS, L, L, WS, R    // both brackets take the enclosed L direction
///
/// After N1:
/// L, L, L, L, L, L, WS, R     // the first space is surrounded by L
///
/// After N2 (final processing types):
/// L, L, L, L, L, L, L, R      // the second space uses embedding direction L
pub fn resolve(
    allocator: std.mem.Allocator,
    sequence: IsolatingRunSequence,
    codepoints: []const u21,
    original: []const BidiCharType,
    processing: []BidiCharType,
) !void {
    std.debug.assert(codepoints.len == original.len and original.len == processing.len);

    try pairedBrackets(allocator, sequence, codepoints, original, processing);
    neutralSequences(sequence, processing);
}

/// [N0]Assigns a direction to both brackets using enclosed text and preceding context.
/// Processes pairs in opening order within this isolating run sequence.
/// Following original NSMs inherit the resolved bracket's direction.
/// Pairs with no enclosed L, R, EN or AN keep their types for N1–N2.
fn pairedBrackets(
    allocator: std.mem.Allocator,
    sequence: IsolatingRunSequence,
    codepoints: []const u21,
    original: []const BidiCharType,
    processing: []BidiCharType,
) !void {
    const pairs = try defs.identifyBracketPairs(allocator, sequence.indices, codepoints, processing);
    defer allocator.free(pairs);
    for (pairs) |pair| {
        const direction = pairDirection(sequence, processing, pair) orelse continue;
        setBracket(sequence.indices, original, processing, pair.open, direction);
        setBracket(sequence.indices, original, processing, pair.close, direction);
    }
}

fn pairDirection(sequence: IsolatingRunSequence, processing: []const BidiCharType, pair: defs.BracketPair) ?BidiCharType {
    const embedding = defs.embeddingDirection(sequence.level);
    var opposite = false;
    for (sequence.indices[pair.open + 1 .. pair.close]) |index| {
        const direction = processing[index].contextDirection() orelse continue;
        if (direction == embedding) return embedding;
        opposite = true;
    }
    if (!opposite) return null;
    return precedingDirection(sequence, processing, pair.open);
}

fn precedingDirection(sequence: IsolatingRunSequence, processing: []const BidiCharType, position: usize) BidiCharType {
    var i = position;
    while (i > 0) {
        i -= 1;
        if (processing[sequence.indices[i]].contextDirection()) |direction| return direction;
    }
    return sequence.sos;
}

fn setBracket(
    indices: []const usize,
    original: []const BidiCharType,
    processing: []BidiCharType,
    position: usize,
    direction: BidiCharType,
) void {
    processing[indices[position]] = direction;
    var i = position + 1;
    while (i < indices.len and original[indices[i]] == .NSM) : (i += 1)
        processing[indices[i]] = direction;
}

/// [N1–N2]Use matching surrounding directions, otherwise the embedding direction.
fn neutralSequences(sequence: IsolatingRunSequence, processing: []BidiCharType) void {
    var previous = sequence.sos;
    var i: usize = 0;
    while (i < sequence.indices.len) {
        if (!processing[sequence.indices[i]].isNI()) {
            previous = processing[sequence.indices[i]].contextDirection().?;
            i += 1;
            continue;
        }
        const start = i;
        while (i < sequence.indices.len and processing[sequence.indices[i]].isNI()) : (i += 1) {}
        const after = if (i < sequence.indices.len)
            processing[sequence.indices[i]].contextDirection().?
        else
            sequence.eos;

        const direction = if (previous == after) previous else defs.embeddingDirection(sequence.level);
        for (sequence.indices[start..i]) |index| processing[index] = direction;
    }
}

test "bidi neutral N0: brackets follow enclosed text and preceding context" {
    const original = [_]BidiCharType{ .R, .ON, .R, .ON };
    var processing = original;
    var indices = [_]usize{ 0, 1, 2, 3 };
    const sequence: IsolatingRunSequence = .{
        .indices = &indices,
        .level = 0,
        .sos = .L,
        .eos = .L,
    };

    try resolve(
        std.testing.allocator,
        sequence,
        &.{ 0x05d0, '(', 0x05d1, ')' },
        &original,
        &processing,
    );

    try std.testing.expectEqualSlices(BidiCharType, &.{ .R, .R, .R, .R }, &processing);
}

test "bidi neutral N1: space between numbers takes R" {
    var processing = [_]BidiCharType{ .EN, .WS, .AN };
    var indices = [_]usize{ 0, 1, 2 };
    const sequence: IsolatingRunSequence = .{
        .indices = &indices,
        .level = 0,
        .sos = .L,
        .eos = .L,
    };

    neutralSequences(sequence, &processing);

    try std.testing.expectEqualSlices(BidiCharType, &.{ .EN, .R, .AN }, &processing);
}

test "bidi neutral N2: different surrounding directions use embedding direction" {
    var processing = [_]BidiCharType{ .L, .WS, .R };
    var indices = [_]usize{ 0, 1, 2 };
    const sequence: IsolatingRunSequence = .{
        .indices = &indices,
        .level = 1,
        .sos = .R,
        .eos = .R,
    };

    neutralSequences(sequence, &processing);

    try std.testing.expectEqualSlices(BidiCharType, &.{ .L, .R, .R }, &processing);
}
