//! Collects and preprocesses text for inline layout.
const Paragraph = @This();
const std = @import("std");
const ComputedStyle = @import("../../style/computed/ComputedStyle.zig");
const LayoutBox = @import("../LayoutBox.zig");
const Text = @import("../../dom/Text.zig");
const TextSequence = @import("../TextSequence.zig");
const ascii = @import("../../utils/ascii.zig");
const Font = @import("../../font/platform.zig").backend.Font;
const Bidi = @import("Bidi.zig");

/// A contiguous range of text that shares the same computed style.
///
/// The range is expressed as a half-open interval `[start, end)` into
/// `Paragraph.bytes`. Both offsets are UTF-8 byte offsets, not character
/// indices.
///
/// The optional font and cached widths can be populated by later layout
/// stages that perform font matching and text measurement.
pub const Span = struct {
    start: usize,
    end: usize,
    style: *const ComputedStyle,
    font: ?Font = null,
    space_width: f64 = 0,
    zero_width: f64 = 0,
};

bytes: std.ArrayList(u8) = .empty,
spans: std.ArrayList(Span) = .empty,
/// Inline CSS bidi scopes, kept out of the visible UTF-8 text.
bidi_events: std.ArrayList(Bidi.Event) = .empty,
pending_event_start: usize = 0,
/// The style associated with a collapsible whitespace sequence that has not
/// yet been emitted.
pending_space: ?*const ComputedStyle = null,
/// Whether the most recently processed byte was a carriage return `\r`.
after_cr: bool = false,

pub fn deinit(self: *Paragraph, allocator: std.mem.Allocator) void {
    for (self.spans.items) |span| if (span.font) |font| font.deinit();
    self.bytes.deinit(allocator);
    self.spans.deinit(allocator);
    self.bidi_events.deinit(allocator);
}

/// Collects text from the sibling layout boxes.
pub fn collect(self: *Paragraph, allocator: std.mem.Allocator, first: ?*LayoutBox) anyerror!void {
    var child = first;
    while (child) |box| : (child = box.next_sibling()) {
        switch (box.content) {
            .text => |sequence| try self.appendSequence(allocator, sequence),
            .inline_level => |inline_box| switch (inline_box) {
                .inline_box => |inline_content| {
                    const scope = Bidi.Scope.forStyle(&inline_content.base.style.values, false);
                    try self.addBidiScope(allocator, scope, true);
                    try self.collect(allocator, box.first_child());
                    try self.addBidiScope(allocator, scope, false);
                },
                .atomic => return error.UnsupportedAtomicInline,
            },
            .block_level => return error.UnexpectedBlockInInline,
        }
    }
}

pub fn addBidiScope(self: *Paragraph, allocator: std.mem.Allocator, scope: Bidi.Scope, opening: bool) !void {
    if (scope.start.len == 0) return;
    try self.bidi_events.append(allocator, .{ .offset = self.bytes.items.len, .scope = scope, .opening = opening });
}

fn appendSequence(self: *Paragraph, allocator: std.mem.Allocator, sequence: TextSequence) !void {
    var node = sequence.first;
    while (true) {
        try self.append(allocator, node.node.downcast(Text).data.slice(), &node.style);
        if (node == sequence.last) break;
        node = node.next_sibling().?;
    }
}

/// Collapse across text nodes and inline element boundaries.
pub fn append(
    self: *Paragraph,
    allocator: std.mem.Allocator,
    text: []const u8,
    style: *const ComputedStyle,
) !void {
    for (text) |byte| {
        if (byte == '\n' and self.after_cr) {
            self.after_cr = false;
            continue;
        }
        self.after_cr = byte == '\r';
        try self.appendByte(
            allocator,
            if (byte == '\r') '\n' else byte,
            style,
        );
    }
}

fn appendByte(
    self: *Paragraph,
    allocator: std.mem.Allocator,
    byte: u8,
    style: *const ComputedStyle,
) !void {
    const mode = style.values.white_space;
    if (byte == '\n' and mode.preservesBreaks()) {
        self.pending_space = null;
        return self.emit(allocator, byte, style);
    }
    if ((ascii.isSpaceOrTab(u8, byte) or byte == '\n') and mode.collapses()) {
        if (self.pending_space == null) {
            self.pending_space = style;
            self.pending_event_start = self.bidi_events.items.len;
        }
        return;
    }
    if (self.pending_space) |pending| {
        self.pending_space = null;
        if (self.bytes.items.len != 0 and self.bytes.items[self.bytes.items.len - 1] != '\n') {
            // The collapsed space precedes CSS scopes entered after its source whitespace.
            for (self.bidi_events.items[self.pending_event_start..]) |*event| event.offset += 1;
            try self.emit(allocator, ' ', pending);
        }
    }
    try self.emit(allocator, byte, style);
}

fn emit(
    self: *Paragraph,
    allocator: std.mem.Allocator,
    byte: u8,
    style: *const ComputedStyle,
) !void {
    const start = self.bytes.items.len;
    try self.bytes.append(allocator, byte);
    if (self.spans.items.len != 0) {
        const last = &self.spans.items[self.spans.items.len - 1];
        if (std.meta.eql(last.style.values, style.values)) {
            last.end += 1;
            return;
        }
    }
    try self.spans.append(allocator, .{
        .start = start,
        .end = start + 1,
        .style = style,
    });
}

pub fn spanAt(self: *const Paragraph, offset: usize) usize {
    for (self.spans.items, 0..) |span, index| {
        if (offset >= span.start and offset < span.end) return index;
    }
    unreachable;
}
