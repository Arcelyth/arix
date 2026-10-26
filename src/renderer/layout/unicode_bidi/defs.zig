//! 3.1 Definitions
const std = @import("std");

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
        if (self.isNeutral() or self.isIsolate()) return true;
        return false;
    }
};

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
    sos: BidiCharType,
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
    sos: BidiCharType,
    eos: BidiCharType,

    pub fn deinit(self: IsolatingRunSequence, allocator: std.mem.Allocator) void {
        allocator.free(self.indices);
    }
};
