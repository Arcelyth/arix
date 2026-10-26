//! 3.1 Definitions
const std = @import("std");
const data = @import("bidi_brackets");

// The same as BidiClass.
// Replace with
// pub const BidiCharType = BidiClass;
// when unicode module has been implemented.
/// https://www.unicode.org/reports/tr9/#Bidirectional_Character_Types
pub const BidiCharType = enum {
    L,
    R,
    AL,
    EN,
    ES,
    ET,
    AN,
    CS,
    NSM,
    BN,
    B,
    S,
    WS,
    ON,
    LRE,
    LRO,
    RLE,
    RLO,
    PDF,
    LRI,
    RLI,
    FSI,
    PDI,

    pub inline fn isStrong(self: BidiCharType) bool {
        return switch (self) {
            .L, .R, .AL => true,
            else => false,
        };
    }

    pub inline fn isWeak(self: BidiCharType) bool {
        return switch (self) {
            .En, .ES, .ET, .AN, .CS, .NSM, .BN => true,
            else => false,
        };
    }

    pub inline fn isNeutral(self: BidiCharType) bool {
        return switch (self) {
            .B, .S, .WS, .ON => true,
            else => false,
        };
    }

    pub inline fn isExplicitFormatting(self: BidiCharType) bool {
        return switch (self) {
            .LRE, .LRO, .RLE, .RLO, .PDF, .LRI, .RLI, .FSI, .PDI => true,
            else => false,
        };
    }

    /// https://www.unicode.org/reports/tr9/#Explicit_Directional_Isolates
    pub inline fn isIsolate(self: BidiCharType) bool {
        return self == .LRI or self == .RLI or self == .FSI;
    }

    pub const isIsolateInitiator = isIsolate;

    pub inline fn isEmbeddingInitiator(self: BidiCharType) bool {
        return switch (self) {
            .LRE, .RLE, .LRO, .RLO => true,
            else => false,
        };
    }

    /// https://www.unicode.org/reports/tr9/#X9
    pub inline fn isRemoved(self: BidiCharType) bool {
        return switch (self) {
            .LRE, .RLE, .LRO, .RLO, .PDF, .BN => true,
            else => false,
        };
    }

    /// Neutral or Isolate formatting character.
    pub inline fn isNI(self: BidiCharType) bool {
        return self.isNeutral() or self.isIsolate() or self == .PDI;
    }

    /// For N0, EN and AN influence surrounding characters as R.
    pub inline fn contextDirection(self: BidiCharType) ?BidiCharType {
        return switch (self) {
            .L => .L,
            .R, .EN, .AN => .R,
            else => null,
        };
    }
};

/// Lookup bidiCharType from a codepoint.
pub fn bidiClass(codepoint: u21) BidiCharType {
    return @import("bidi_classes").bidiClass(BidiCharType, codepoint);
}

/// [BD2]Embedding levels start at zero and explicit levels cannot exceed 125.
pub const EmbeddingLevel = u8;
pub const max_depth: EmbeddingLevel = 125;

pub inline fn isValidExplicitLevel(level: EmbeddingLevel) bool {
    return level <= max_depth;
}

/// [BD3]Even levels have direction L, odd levels have direction R.
pub inline fn embeddingDirection(level: EmbeddingLevel) BidiCharType {
    return if (level & 1 == 0) .L else .R;
}

pub const ParagraphLevel = u1;

/// [BD6]Determines whether the bidirectional type of characters is to be reset.
pub const DirectionalOverrideStatus = enum {
    neutral,
    ltr,
    rtl,

    pub inline fn reset(self: DirectionalOverrideStatus) ?BidiCharType {
        return switch (self) {
            .neutral => null,
            .ltr => .L,
            .rtl => .R,
        };
    }
};

pub const DirectionalStatus = struct {
    level: EmbeddingLevel,
    override: DirectionalOverrideStatus = .neutral,
    /// True when an isolate initiator started current embedding level.
    isolate: bool = false,
};

/// [BD7]A maximal same-level range in the filtered index array.
pub const LevelRun = struct {
    start: usize,
    end: usize,
    level: u8,
    /// Start of sequence.
    sos: BidiCharType,
    /// End of sequence.
    eos: BidiCharType,
    next: ?usize = null,
    /// Mark a level run that continues an existing isolating run sequence.
    continuation: bool = false,
};

/// [BD9]Maps isolate initiators to matching PDIs.
/// Matching ignores the explicit-depth limit and stops at paragraph boundaries.
pub fn isolateMatches(allocator: std.mem.Allocator, original: []const BidiCharType) ![]?usize {
    const matches = try allocator.alloc(?usize, original.len);
    errdefer allocator.free(matches);
    @memset(matches, null);

    const stack = try allocator.alloc(usize, original.len);
    defer allocator.free(stack);
    var len: usize = 0;
    for (original, 0..) |class, i| {
        if (class == .B) {
            len = 0;
        } else if (class.isIsolateInitiator()) {
            stack[len] = i;
            len += 1;
        } else if (class == .PDI and len > 0) {
            len -= 1;
            matches[stack[len]] = i;
            matches[i] = stack[len];
        }
    }
    return matches;
}

pub const IsolatingRunSequence = struct {
    indices: []usize,
    level: u8,
    /// Start of sequence.
    sos: BidiCharType,
    /// End of sequence.
    eos: BidiCharType,

    pub fn deinit(self: IsolatingRunSequence, allocator: std.mem.Allocator) void {
        allocator.free(self.indices);
    }
};

pub const BracketPair = struct { open: usize, close: usize };
const Opening = struct { position: usize, close: u21 };
pub const max_bracket_openings = 63;

pub fn pairedBracket(codepoint: u21, current: BidiCharType) ?data.Bracket {
    return if (current == .ON) lookup(codepoint) else null;
}

/// [BD16]Find pairs in opening-position order, excluding other isolates.
pub fn identifyBracketPairs(
    allocator: std.mem.Allocator,
    indices: []const usize,
    codepoints: []const u21,
    processing: []const BidiCharType,
) ![]BracketPair {
    var pairs: std.ArrayList(BracketPair) = .empty;
    errdefer pairs.deinit(allocator);
    var stack: [max_bracket_openings]Opening = undefined;
    var len: usize = 0;
    for (indices, 0..) |index, position| {
        const bracket = pairedBracket(codepoints[index], processing[index]) orelse continue;
        if (bracket.is_open) {
            if (len == stack.len) {
                pairs.clearRetainingCapacity();
                break;
            }
            stack[len] = .{
                .position = position,
                .close = canonical(bracket.pair),
            };
            len += 1;
        } else if (findOpening(stack[0..len], canonical(codepoints[index]))) |opening| {
            try pairs.append(allocator, .{
                .open = stack[opening].position,
                .close = position,
            });
            len = opening;
        }
    }
    std.mem.sort(BracketPair, pairs.items, {}, before);
    return pairs.toOwnedSlice(allocator);
}

fn before(_: void, a: BracketPair, b: BracketPair) bool {
    return a.open < b.open;
}

inline fn findOpening(stack: []const Opening, close: u21) ?usize {
    var i = stack.len;
    while (i > 0) {
        i -= 1;
        if (stack[i].close == close) return i;
    }
    return null;
}

fn canonical(codepoint: u21) u21 {
    return if (codepoint == 0x232a) 0x3009 else codepoint;
}

fn lookup(codepoint: u21) ?data.Bracket {
    var low: usize = 0;
    var high = data.entries.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const entry = data.entries[mid];
        if (codepoint < entry.codepoint) {
            high = mid;
        } else if (codepoint > entry.codepoint) {
            low = mid + 1;
        } else return entry;
    }
    return null;
}

test "bidi defs: nested isolates and paragraph boundaries" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const matches = try isolateMatches(allocator, &.{ .LRI, .RLI, .PDI, .PDI, .B, .FSI, .B, .PDI });
    defer allocator.free(matches);

    try testing.expectEqualSlices(?usize, &.{ 3, 2, 1, 0, null, null, null, null }, matches);
}

test "bidi defs: nested bracket pairs in opening order" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const pairs = try identifyBracketPairs(
        allocator,
        &.{ 0, 1, 2, 3, 4, 5 },
        &.{ '(', 'a', '[', 'b', ']', ')' },
        &.{ .ON, .L, .ON, .L, .ON, .ON },
    );
    defer allocator.free(pairs);

    try testing.expectEqualDeep(&[_]BracketPair{
        .{ .open = 0, .close = 5 },
        .{ .open = 2, .close = 4 },
    }, pairs);
    try testing.expectEqual(null, pairedBracket('(', .L));
}
