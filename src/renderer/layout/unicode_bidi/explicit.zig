//! Explicit embeddings, overrides, and isolates: X1–X8.
//! https://www.unicode.org/reports/tr9/#Explicit_Levels_and_Directions
const std = @import("std");
const BidiCharType = @import("types.zig").BidiCharType;

/// Maximum explicit embedding level, specified by UAX #9 BD2.
const max_depth = 125;

const Entry = struct {
    level: u8,
    override: ?BidiCharType = null,
    isolate: bool = false,
};

const State = struct {
    stack: [max_depth + 2]Entry = undefined,
    len: usize = 1,
    overflow_isolates: usize = 0,
    overflow_embeddings: usize = 0,
    valid_isolates: usize = 0,

    /// `base` is the paragraph’s base embedding level,
    /// determined by P2–P3 or supplied by the caller.
    fn init(base: u1) State {
        var state: State = .{};
        state.stack[0] = .{ .level = base };
        return state;
    }

    fn top(self: *const State) Entry {
        return self.stack[self.len - 1];
    }

    /// [X2–X5b]Push the next odd/even level.
    fn push(self: *State, class: BidiCharType) void {
        const rtl = class == .RLE or class == .RLO or class == .RLI;
        const current = self.top().level;
        // Get the smallest odd/even level greater than current.
        const level = if (rtl) (current + 1) | 1 else (current + 2) & ~@as(u8, 1);
        const isolate = class.isIsolate();

        if (isValid(level) and self.overflow_isolates == 0 and self.overflow_embeddings == 0) {
            self.stack[self.len] = .{
                .level = level,
                .override = switch (class) {
                    .RLO => .R,
                    .LRO => .L,
                    else => null,
                },
                .isolate = isolate,
            };
            self.len += 1;
            if (isolate) self.valid_isolates += 1;
        } else if (isolate)
            self.overflow_isolates += 1
        else if (self.overflow_isolates == 0)
            self.overflow_embeddings += 1;
    }

    /// [X6a]PDI closes an isolate and all embeddings inside it.
    fn popIsolate(self: *State) void {
        if (self.overflow_isolates > 0) {
            self.overflow_isolates -= 1;
        } else if (self.valid_isolates > 0) {
            self.overflow_embeddings = 0;
            while (!self.top().isolate) self.len -= 1;
            self.len -= 1;
            self.valid_isolates -= 1;
        }
    }

    /// [X7]PDF cannot pop an isolate or the paragraph's initial status.
    fn popEmbedding(self: *State) void {
        if (self.overflow_isolates > 0) return;
        if (self.overflow_embeddings > 0) {
            self.overflow_embeddings -= 1;
        } else if (self.len > 1 and !self.top().isolate) self.len -= 1;
    }

    inline fn applyOverride(self: *const State, class: *BidiCharType) void {
        if (self.top().override) |value| class.* = value;
    }

    fn process(self: *State, original: BidiCharType, working: *BidiCharType) u8 {
        const level = self.top().level;
        switch (original) {
            .LRE, .RLE, .LRO, .RLO => self.push(original),
            .LRI, .RLI, .FSI => {
                const direction = working.*;
                working.* = original;
                self.applyOverride(working);
                self.push(direction);
            },
            .PDI => {
                self.popIsolate();
                self.applyOverride(working);
                return self.top().level;
            },
            .PDF => {
                self.popEmbedding();
                return self.top().level;
            },
            .B => return self.stack[0].level,
            .BN => {},
            else => self.applyOverride(working),
        }
        return level;
    }
};

inline fn isValid(level: u8) bool {
    return level <= max_depth;
}

/// [X5c]Determine each FSI's direction from its first strong character outside
/// nested isolates.
/// Unresolved FSIs default to LRI, regardless of paragraph level.
fn firstStrongIsolates(allocator: std.mem.Allocator, original: []const BidiCharType, processing: []BidiCharType) !void {
    var stack: std.ArrayList(usize) = .empty;
    defer stack.deinit(allocator);

    for (original, 0..) |class, i| {
        if (class.isIsolate()) {
            try stack.append(allocator, i);
        } else if (class == .PDI) {
            _ = stack.pop();
        } else if (class.isStrong() and stack.items.len > 0) {
            const initiator = stack.items[stack.items.len - 1];
            if (processing[initiator] == .FSI)
                processing[initiator] = if (class == .L) .LRI else .RLI;
        }
    }
    for (processing) |*class| if (class.* == .FSI) {
        class.* = .LRI;
    };
}

/// Resolves one P1 paragraph into caller-owned output slices of the same length.
pub fn resolve(
    allocator: std.mem.Allocator,
    original: []const BidiCharType,
    base: u1,
    levels: []u8,
    processing: []BidiCharType,
) !void {
    std.debug.assert(original.len == levels.len and original.len == processing.len);

    @memcpy(processing, original);
    try firstStrongIsolates(allocator, original, processing);
    var state = State.init(base);
    for (original, processing, levels) |class, *working, *level|
        level.* = state.process(class, working);
}

test "bidi X1-X8: nested embeddings and PDF" {
    const testing = @import("std").testing;

    const original = [_]BidiCharType{ .LRE, .R, .RLE, .L, .PDF, .AL, .PDF, .B };
    var levels: [original.len]u8 = undefined;
    var processing: [original.len]BidiCharType = undefined;
    try resolve(testing.allocator, &original, 0, &levels, &processing);

    try testing.expectEqualSlices(u8, &.{ 0, 2, 2, 3, 2, 2, 0, 0 }, &levels);
    try testing.expectEqualSlices(BidiCharType, &original, &processing);
}

test "bidi X1-X8: overrides stop inside isolates and resume after PDI" {
    const testing = @import("std").testing;

    const original = [_]BidiCharType{ .RLO, .L, .LRI, .R, .PDF, .PDI, .AL, .BN, .PDF, .L };
    var levels: [original.len]u8 = undefined;
    var processing: [original.len]BidiCharType = undefined;
    try resolve(testing.allocator, &original, 0, &levels, &processing);

    try testing.expectEqualSlices(u8, &.{ 0, 1, 1, 2, 2, 1, 1, 1, 0, 0 }, &levels);
    try testing.expectEqualSlices(BidiCharType, &.{ .RLO, .R, .R, .R, .PDF, .R, .R, .BN, .PDF, .L }, &processing);
}

test "bidi X5c: FSI skips nested isolates and defaults to LTR" {
    const testing = @import("std").testing;

    const original = [_]BidiCharType{ .FSI, .LRI, .R, .PDI, .AL, .PDI, .L };
    var levels: [original.len]u8 = undefined;
    var processing: [original.len]BidiCharType = undefined;
    try resolve(testing.allocator, &original, 0, &levels, &processing);
    try testing.expectEqualSlices(u8, &.{ 0, 1, 2, 1, 1, 0, 0 }, &levels);
    try testing.expectEqualSlices(BidiCharType, &original, &processing);

    const neutral = [_]BidiCharType{ .FSI, .EN, .PDI };
    try resolve(testing.allocator, &neutral, 1, levels[0..neutral.len], processing[0..neutral.len]);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 1 }, levels[0..neutral.len]);
}

test "bidi X6a-X7: overflow scopes and PDI restore valid state" {
    const testing = @import("std").testing;

    const suffix = [_]BidiCharType{ .LRE, .RLI, .PDF, .PDI, .PDF, .PDI, .L, .B };
    var original: [max_depth + suffix.len]BidiCharType = undefined;
    for (original[0..max_depth], 0..) |*class, i|
        class.* = if (i == 0) .RLI else if (i & 1 == 1) .LRE else .RLE;

    @memcpy(original[max_depth..], &suffix);
    var levels: [original.len]u8 = undefined;
    var processing: [original.len]BidiCharType = undefined;
    try resolve(testing.allocator, &original, 0, &levels, &processing);

    try testing.expectEqualSlices(u8, &.{ 125, 125, 125, 125, 125, 0, 0, 0 }, levels[max_depth..]);
}

test "bidi X5-X7: LRO, unmatched controls and isolate termination" {
    const testing = @import("std").testing;

    const original = [_]BidiCharType{ .PDF, .PDI, .LRO, .AL, .FSI, .EN, .PDI, .PDF, .AL };
    var levels: [original.len]u8 = undefined;
    var processing: [original.len]BidiCharType = undefined;
    try resolve(testing.allocator, &original, 1, &levels, &processing);

    try testing.expectEqualSlices(u8, &.{ 1, 1, 1, 2, 2, 4, 2, 1, 1 }, &levels);
    try testing.expectEqualSlices(BidiCharType, &.{ .PDF, .PDI, .LRO, .L, .L, .EN, .L, .PDF, .AL }, &processing);
}
