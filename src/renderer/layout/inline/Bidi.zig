//! Connects CSS bidi scopes and UTF-8 inline text to UAX #9(UBA).
const Bidi = @This();
const std = @import("std");
const defs = @import("../unicode_bidi/defs.zig");
const BidiInfo = @import("../unicode_bidi/BidiInfo.zig");
const ComputedValues = @import("../../css/properties/registry.zig").ComputedValues;
const Paragraph = @import("Paragraph.zig");

pub const Level = defs.EmbeddingLevel;

/// Records where an inline element opens or closes its CSS bidi scope.
pub const Event = struct {
    /// UTF-8 boundary in the preprocessed paragraph text.
    offset: usize,
    /// Controls associated with the element's direction and unicode-bidi values.
    scope: Scope,
    /// True at the element's start; false at its end.
    opening: bool,
};

/// https://drafts.csswg.org/css-writing-modes-3/#unicode-bidi
pub const Scope = struct {
    start: []const u21 = &.{},
    end: []const u21 = &.{},

    pub fn forStyle(style: *const ComputedValues, root: bool) Scope {
        const rtl = style.direction == .rtl;
        if (root) return switch (style.unicode_bidi) {
            .@"bidi-override", .@"isolate-override" => .{
                .start = if (rtl) &.{0x202e} else &.{0x202d},
                .end = &.{0x202c},
            },
            else => .{},
        };
        return switch (style.unicode_bidi) {
            .normal => .{},
            .embed => .{
                .start = if (rtl) &.{0x202b} else &.{0x202a},
                .end = &.{0x202c},
            },
            .isolate => .{
                .start = if (rtl) &.{0x2067} else &.{0x2066},
                .end = &.{0x2069},
            },
            .@"bidi-override" => .{
                .start = if (rtl) &.{0x202e} else &.{0x202d},
                .end = &.{0x202c},
            },
            .@"isolate-override" => .{
                .start = if (rtl) &.{ 0x2068, 0x202e } else &.{ 0x2068, 0x202d },
                .end = &.{ 0x202c, 0x2069 },
            },
            .plaintext => .{
                .start = &.{0x2068},
                .end = &.{0x2069},
            },
        };
    }
};

info: BidiInfo,
/// Maps each rendered UTF-8 byte to its position in the analysis text.
///
/// For example:
/// Visible text:   a, b
/// Analysis text:  RLI, a, b, PDI
/// indices:        1, 2, 4
indices: []usize,

pub fn init(allocator: std.mem.Allocator, paragraph: *const Paragraph, style: *const ComputedValues) !Bidi {
    const bytes = paragraph.bytes.items;
    const indices = try allocator.alloc(usize, bytes.len + 1);
    errdefer allocator.free(indices);

    var builder: Builder = .{};
    defer builder.deinit(allocator);
    const root = Scope.forStyle(style, true);

    try builder.open(allocator, root);
    try builder.appendText(allocator, bytes, paragraph.bidi_events.items, indices);
    try builder.close(allocator, root);
    indices[bytes.len] = builder.text.items.len;
    const base: ?defs.ParagraphLevel = if (style.unicode_bidi == .plaintext)
        null
    else if (style.direction == .rtl)
        1
    else
        0;

    return .{
        .info = try BidiInfo.init(allocator, builder.text.items, base),
        .indices = indices,
    };
}

pub fn deinit(self: Bidi, allocator: std.mem.Allocator) void {
    self.info.deinit(allocator);
    allocator.free(self.indices);
}

pub fn paragraphAt(self: *const Bidi, offset: usize) BidiInfo.ParagraphInfo {
    const index = self.indices[offset];
    for (self.info.paragraphs) |para| {
        if (index >= para.range.start and index < para.range.end) return para;
    }
    unreachable;
}

/// L1 uses the entire line, including whitespace that will be trimmed for painting.
pub fn lineLevels(self: *const Bidi, allocator: std.mem.Allocator, start: usize, end: usize) ![]Level {
    const para = self.paragraphAt(start);
    return self.info.reorderedLevels(allocator, para, .{
        .start = self.indices[start],
        .end = @min(self.indices[end], para.range.end),
    });
}

/// A visible UTF-8 byte range [start, end) with one resolved embedding level.
pub const Run = struct {
    start: usize,
    end: usize,
    level: Level,
};

/// Splits visible UTF-8 text by level, omitting source bidi formatting controls.
pub fn runs(self: *const Bidi, start: usize, end: usize, levels: []const Level) RunIterator {
    return .{ .bidi = self, .position = start, .end = end, .levels = levels };
}

pub const RunIterator = struct {
    bidi: *const Bidi,
    position: usize,
    end: usize,
    levels: []const Level,

    /// Returns the next range to shape, or null at the end of the requested text.
    pub fn next(self: *RunIterator) ?Run {
        while (self.position < self.end and self.formatting(self.position)) self.position += 1;
        if (self.position == self.end) return null;
        const start = self.position;
        const level = self.levels[self.bidi.indices[start]];
        self.position += 1;
        while (self.position < self.end and !self.formatting(self.position) and
            self.levels[self.bidi.indices[self.position]] == level) self.position += 1;
        return .{ .start = start, .end = self.position, .level = level };
    }

    fn formatting(self: *const RunIterator, offset: usize) bool {
        return self.bidi.info.original_classes[self.bidi.indices[offset]].isExplicitFormatting();
    }
};

/// Temporary helper that constructs the input to BidiInfo.
/// Decodes visible UTF-8 text, inserts controls at Event boundaries, and tracks
const Builder = struct {
    /// Logical code points, including source characters and CSS-generated controls.
    text: std.ArrayList(u21) = .empty,
    scopes: std.ArrayList(Scope) = .empty,

    fn deinit(self: *Builder, allocator: std.mem.Allocator) void {
        self.text.deinit(allocator);
        self.scopes.deinit(allocator);
    }

    /// Inserts a scope's start controls and remembers it until its closing event.
    fn open(self: *Builder, allocator: std.mem.Allocator, scope: Scope) !void {
        if (scope.start.len == 0) return;
        try self.scopes.append(allocator, scope);
        try self.text.appendSlice(allocator, scope.start);
    }

    /// Inserts the matching end controls and removes the innermost CSS scope.
    fn close(self: *Builder, allocator: std.mem.Allocator, scope: Scope) !void {
        if (scope.start.len == 0) return;
        try self.text.appendSlice(allocator, scope.end);
        _ = self.scopes.pop();
    }

    fn appendText(
        self: *Builder,
        allocator: std.mem.Allocator,
        bytes: []const u8,
        events: []const Event,
        indices: []usize,
    ) !void {
        var iterator = (try std.unicode.Utf8View.init(bytes)).iterator();
        var event: usize = 0;
        while (iterator.nextCodepointSlice()) |character| {
            const start = iterator.i - character.len;
            try self.eventsAt(allocator, events, &event, start);

            const cp = std.unicode.utf8Decode(character) catch unreachable;
            const paragraph_break = defs.bidiClass(cp) == .B;
            if (paragraph_break) try self.closeScopes(allocator);
            @memset(indices[start..iterator.i], self.text.items.len);
            try self.text.append(allocator, cp);
            if (paragraph_break) try self.reopenScopes(allocator);
        }
        try self.eventsAt(allocator, events, &event, bytes.len);
        std.debug.assert(event == events.len);
    }

    fn eventsAt(
        self: *Builder,
        allocator: std.mem.Allocator,
        events: []const Event,
        cursor: *usize,
        offset: usize,
    ) !void {
        while (cursor.* < events.len and events[cursor.*].offset == offset) : (cursor.* += 1) {
            const event = events[cursor.*];
            if (event.opening)
                try self.open(allocator, event.scope)
            else
                try self.close(allocator, event.scope);
        }
    }

    /// CSS scopes close and reopen at paragraph boundaries (Writing Modes §2.4.4).
    fn closeScopes(self: *Builder, allocator: std.mem.Allocator) !void {
        var i = self.scopes.items.len;
        while (i > 0) {
            i -= 1;
            try self.text.appendSlice(allocator, self.scopes.items[i].end);
        }
    }

    fn reopenScopes(self: *Builder, allocator: std.mem.Allocator) !void {
        for (self.scopes.items) |scope| try self.text.appendSlice(allocator, scope.start);
    }
};
