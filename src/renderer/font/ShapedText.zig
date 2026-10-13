const ShapedText = @This();
const std = @import("std");
const Font = @import("platform.zig").backend.Font;
const Point = @import("../geometry.zig").Point;

pub const Direction = enum { ltr, rtl };

pub const Glyph = struct {
    id: u16,
    /// Byte offset in the input UTF-8 text. Multiple glyphs may share an offset.
    cluster: usize,
    /// Relative to the text's baseline origin, in CSS pixels with Y increasing upward.
    position: Point,
    advance: Point,
};

pub const Run = struct {
    /// Owned actual font, including any platform fallback.
    font: Font,
    direction: Direction,
    glyphs: []Glyph,
    /// UTF-8 byte range in the input text, with an exclusive end.
    text_range: struct { start: usize, end: usize },
    /// Columns (a, b), (c, d), (tx, ty).
    text_matrix: [3]Point,

    pub fn deinit(self: Run, allocator: std.mem.Allocator) void {
        self.font.deinit();
        allocator.free(self.glyphs);
    }
};

/// Runs retain their shaped positions. All data is independent of the input text and font.
runs: []Run,
width: f64,
ascent: f64,
descent: f64,
leading: f64,

pub fn deinit(self: ShapedText, allocator: std.mem.Allocator) void {
    for (self.runs) |run| run.deinit(allocator);
    allocator.free(self.runs);
}
