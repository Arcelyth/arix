//! Measures paragraph text before line breaking. Shaped advances determine
//! how much text fits and cluster boundaries prevent breaks inside shaped clusters.
const std = @import("std");
const Paragraph = @import("Paragraph.zig");
const Matcher = @import("../../font/Matcher.zig");
const shaping = @import("../../font/shaping.zig");
const Font = @import("../../font/platform.zig").backend.Font;

pub const Measurement = struct {
    /// Cumulative shaped advances at each byte boundary.
    widths: []f64,
    /// True at shaped cluster boundaries, including the paragraph end.
    clusters: []bool,

    pub fn deinit(self: Measurement, allocator: std.mem.Allocator) void {
        allocator.free(self.widths);
        allocator.free(self.clusters);
    }

    pub fn width(
        self: Measurement,
        paragraph: *const Paragraph,
        start: usize,
        end: usize,
    ) f64 {
        var cursor = start;
        var x: f64 = 0;
        while (std.mem.indexOfScalarPos(
            u8,
            paragraph.bytes.items[0..end],
            cursor,
            '\t',
        )) |tab| {
            x += self.widths[tab] - self.widths[cursor];
            const span = paragraph.spans.items[paragraph.spanAt(tab)];
            x += tabAdvance(x, span.space_width, span.zero_width);
            cursor = tab + 1;
        }
        return x + self.widths[end] - self.widths[cursor];
    }
};

pub fn measure(allocator: std.mem.Allocator, paragraph: *Paragraph, matcher: Matcher) !Measurement {
    const widths = try allocator.alloc(f64, paragraph.bytes.items.len + 1);
    errdefer allocator.free(widths);
    @memset(widths, 0);

    const clusters = try allocator.alloc(bool, widths.len);
    errdefer allocator.free(clusters);
    @memset(clusters, false);

    clusters[paragraph.bytes.items.len] = true;
    for (paragraph.spans.items) |*span| {
        span.font = try matcher.match(allocator, &span.style.values) orelse return error.FontNotFound;
        if (std.mem.indexOfScalar(u8, paragraph.bytes.items[span.start..span.end], '\t') != null) {
            span.space_width = try glyphWidth(allocator, " ", span.font.?);
            span.zero_width = try glyphWidth(allocator, "0", span.font.?);
        }
        try measureSpan(
            allocator,
            paragraph.bytes.items,
            span.*,
            widths,
            clusters,
        );
    }
    for (1..widths.len) |i| widths[i] += widths[i - 1];
    return .{ .widths = widths, .clusters = clusters };
}

pub fn glyphWidth(allocator: std.mem.Allocator, text: []const u8, font: Font) !f64 {
    const shaped = try shaping.shape(allocator, text, font, .ltr);
    defer shaped.deinit(allocator);

    return shaped.width;
}

/// Measures a span in pieces separated by preserved newlines and tabs.
pub fn measureSpan(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    span: Paragraph.Span,
    widths: []f64,
    clusters: []bool,
) !void {
    var start = span.start;
    while (start < span.end) {
        const end = std.mem.indexOfAnyPos(
            u8,
            bytes[0..span.end],
            start,
            "\n\t",
        ) orelse span.end;

        if (end > start) try measureText(
            allocator,
            bytes[start..end],
            span.font.?,
            start,
            widths,
            clusters,
        );
        clusters[start] = true;
        clusters[end] = true;
        if (end < span.end) clusters[end + 1] = true;
        start = end + 1;
    }
}

pub fn measureText(
    allocator: std.mem.Allocator,
    text: []const u8,
    font: Font,
    start: usize,
    widths: []f64,
    clusters: []bool,
) !void {
    const shaped = try shaping.shape(allocator, text, font, .ltr);
    defer shaped.deinit(allocator);
    for (shaped.runs) |run| for (run.glyphs) |glyph| {
        widths[start + glyph.cluster + 1] += glyph.advance[0];
        clusters[start + glyph.cluster] = true;
    };
}

/// tab-size's initial value is 8 spaces; a tab advances at least 0.5ch.
pub fn tabAdvance(x: f64, space: f64, zero: f64) f64 {
    const interval = 8 * space;
    if (interval <= 0) return 0;
    const remainder = interval - @mod(x, interval);

    return if (remainder < zero / 2) remainder + interval else remainder;
}

test "layout measure: text width and combining cluster boundaries" {
    const names = switch (@import("builtin").os.tag) {
        .macos => .{ "Helvetica", "Helvetica" },
        .windows => .{ "Arial", "ArialMT" },
        .linux => .{ "Liberation Sans", "LiberationSans" },
        else => return error.SkipZigTest,
    };
    const ComputedStyle = @import("../../style/computed/ComputedStyle.zig");
    const allocator = std.testing.allocator;
    const style: ComputedStyle = .{ .values = .{
        .font_size = 16,
        .font_family = .{ .families = &.{.{ .name = names[0] }} },
    } };
    const font = try Font.initWithName(names[1], 16);
    defer font.deinit();
    const text = "e\u{301}x";
    var paragraph: Paragraph = .{};
    defer paragraph.deinit(allocator);
    try paragraph.append(allocator, text, &style);
    const measured = try measure(allocator, &paragraph, .{});
    defer measured.deinit(allocator);

    try std.testing.expectApproxEqAbs(
        try glyphWidth(allocator, text, font),
        measured.width(&paragraph, 0, text.len),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        try glyphWidth(allocator, "x", font),
        measured.width(&paragraph, 3, text.len),
        0.001,
    );
    try std.testing.expectEqualSlices(bool, &.{ true, false, false, true, true }, measured.clusters);
}
