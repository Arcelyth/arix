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

pub const IsolatingRunSequence = struct {
    indices: []usize,
    level: u8,
    sos: BidiCharType,
    eos: BidiCharType,

    pub fn deinit(self: IsolatingRunSequence, allocator: std.mem.Allocator) void {
        allocator.free(self.indices);
    }
};
