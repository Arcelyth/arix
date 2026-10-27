const Line = @This();
const std = @import("std");
const Paragraph = @import("Paragraph.zig");
const Fragment = @import("../fragment/Fragment.zig");
const ComputedStyle = @import("../../style/computed/ComputedStyle.zig");
const ShapedText = @import("../../font/ShapedText.zig");
const Metrics = @import("../../font/Metrics.zig");
const shaping = @import("../../font/shaping.zig");
const line_height = @import("../../css/values/computed/line_height.zig");
const measure = @import("measure.zig");
const Bidi = @import("Bidi.zig");
const reorder = @import("../unicode_bidi/reorder.zig");

/// Temporary line items, positioned after the line's baseline is known.
items: std.ArrayList(Item) = .empty,
/// Vertical extents of the line relative to its baseline.
bounds: line_height.Extents,
/// Total horizontal advance accumulated by the line.
advance: f64 = 0,

const Item = struct {
    start: usize,
    level: Bidi.Level,
    content: union(enum) { text: TextItem, tab: Paragraph.Span },
};

const TextItem = struct {
    run: ShapedText.Run,
    metrics: Metrics,
    style: *const ComputedStyle,
    text: []const u8,
    offset: f64,
    width: f64,

    /// Consumes the run, including on allocation failure.
    fn intoFragment(self: TextItem, allocator: std.mem.Allocator, baseline: f64) !*Fragment {
        errdefer self.run.deinit(allocator);
        const text = try allocator.dupe(u8, self.text);
        errdefer allocator.free(text);
        const fragment = try allocator.create(Fragment);
        fragment.* = Fragment.init(.{ .text = .{
            .base = .{ .rect = .{
                .x = self.offset,
                .y = baseline - self.metrics.ascent,
                .width = self.width,
                .height = self.metrics.ascent + self.metrics.descent,
            } },
            .font_metrics = self.metrics,
            .style = self.style.*,
            .text = text,
            .run = self.run,
        } });
        return fragment;
    }
};

pub fn deinit(self: *Line, allocator: std.mem.Allocator) void {
    for (self.items.items) |item| switch (item.content) {
        .text => |text| text.run.deinit(allocator),
        .tab => {},
    };
    self.items.deinit(allocator);
}

pub fn include(self: *Line, span: Paragraph.Span) void {
    self.includeMetrics(span.style, span.font.?.metrics());
}

fn includeMetrics(self: *Line, style: *const ComputedStyle, metrics: Metrics) void {
    self.bounds.include(line_height.resolve(style.values.line_height, style.values.font_size, metrics));
}

pub fn appendSpan(
    self: *Line,
    allocator: std.mem.Allocator,
    text: []const u8,
    span: Paragraph.Span,
    source_start: usize,
    level: Bidi.Level,
) !void {
    self.include(span);
    var start: usize = 0;
    while (start < text.len) {
        const tab = std.mem.indexOfScalarPos(u8, text, start, '\t') orelse text.len;
        if (tab > start) try self.appendText(allocator, text[start..tab], span, source_start + start, level);
        if (tab < text.len) try self.items.append(allocator, .{
            .start = source_start + tab,
            .level = level,
            .content = .{ .tab = span },
        });
        start = tab + 1;
    }
}

fn appendText(
    self: *Line,
    allocator: std.mem.Allocator,
    text: []const u8,
    span: Paragraph.Span,
    source_start: usize,
    level: Bidi.Level,
) !void {
    const shaped = try shaping.shape(allocator, text, span.font.?, if (level & 1 == 0) .ltr else .rtl);
    errdefer shaped.deinit(allocator);
    try self.items.ensureUnusedCapacity(allocator, shaped.runs.len);

    var offset: f64 = 0;
    for (shaped.runs) |run| offset += self.appendRun(run, text, span.style, offset, source_start, level);
    // The items now own each run's font and glyphs.
    allocator.free(shaped.runs);
}

fn appendRun(
    self: *Line,
    run: ShapedText.Run,
    text: []const u8,
    style: *const ComputedStyle,
    offset: f64,
    source_start: usize,
    level: Bidi.Level,
) f64 {
    const metrics = run.font.metrics();
    const range = run.text_range;
    var width: f64 = 0;
    for (run.glyphs) |*glyph| {
        width += glyph.advance[0];
        glyph.position[0] -= offset;
        glyph.cluster -= range.start;
    }

    var local_run = run;
    local_run.text_range = .{ .start = 0, .end = range.end - range.start };
    self.items.appendAssumeCapacity(.{
        .start = source_start + range.start,
        .level = level,
        .content = .{ .text = .{
            .run = local_run,
            .metrics = metrics,
            .style = style,
            .text = text[range.start..range.end],
            .offset = 0,
            .width = width,
        } },
    });
    self.includeMetrics(style, metrics);
    return width;
}

pub fn finish(
    self: *Line,
    allocator: std.mem.Allocator,
    parent: *Fragment,
    block_offset: f64,
    width: f64,
    rtl: bool,
) !void {
    try self.orderItems(allocator);
    self.positionItems(width, rtl);
    // Pop in visual order so ownership moves to the fragment tree one item at a time.
    std.mem.reverse(Item, self.items.items);
    while (self.items.pop()) |item| switch (item.content) {
        .text => |text| parent.appendChild(try text.intoFragment(allocator, block_offset + self.bounds.above)),
        .tab => {},
    };
}

fn orderItems(self: *Line, allocator: std.mem.Allocator) !void {
    std.mem.sort(Item, self.items.items, {}, logicalOrder);
    const levels = try allocator.alloc(Bidi.Level, self.items.items.len);
    defer allocator.free(levels);
    const order = try allocator.alloc(usize, levels.len);
    defer allocator.free(order);
    const visual = try allocator.alloc(Item, levels.len);
    defer allocator.free(visual);

    for (self.items.items, levels) |item, *level| level.* = item.level;
    reorder.visualOrder(levels, order);
    for (order, visual) |index, *item| item.* = self.items.items[index];
    @memcpy(self.items.items, visual);
}

fn logicalOrder(_: void, a: Item, b: Item) bool {
    return a.start < b.start;
}

fn positionItems(self: *Line, width: f64, rtl: bool) void {
    self.advance = 0;
    for (0..self.items.items.len) |i| {
        const index = if (rtl) self.items.items.len - 1 - i else i;
        switch (self.items.items[index].content) {
            .text => |*text| {
                text.offset = self.advance;
                self.advance += text.width;
            },
            .tab => |span| self.advance += measure.tabAdvance(self.advance, span.space_width, span.zero_width),
        }
    }
    if (rtl) for (self.items.items) |*item| switch (item.content) {
        .text => |*text| text.offset = width - text.offset - text.width,
        .tab => {},
    };
}
