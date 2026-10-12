const std = @import("std");
const InlineFormattingContext = @import("InlineFormattingContext.zig");
const Fragment = @import("../fragment/Fragment.zig");
const Options = @import("../Options.zig");
const Paragraph = @import("Paragraph.zig");
const Measurement = @import("measure.zig").Measurement;
const ascii = @import("../../utils/ascii.zig");
const backend = @import("../../font/platform.zig").backend;

pub const Result = struct {
    height: f64 = 0,
    // Preserved empty lines affect margin collapsing even without text fragments.
    has_line: bool = false,
};

/// Horizontal, baseline-aligned inline text with the initial direction:ltr.
pub fn layout(
    allocator: std.mem.Allocator,
    context: *const InlineFormattingContext,
    parent: *Fragment,
    width: f64,
    options: Options,
) !Result {
    _ = allocator;
    _ = context;
    _ = parent;
    _ = width;
    _ = options;
    @panic("TODO");
}

/// Describes whether a text boundary is a valid line-ending opportunity.
pub const Break = enum {
    /// No line break is allowed at this boundary.
    none,
    /// A line break is allowed but is not required.
    soft,
    /// A line break is required, such as at a preserved newline.
    forced,
};

/// Computes line-breaking opportunities for every byte boundary in a paragraph.
///
/// The returned slice has `paragraph.bytes.items.len + 1` entries. Each index
/// represents a boundary in the UTF-8 text, including the boundary before the
/// first byte and the boundary after the last byte.
pub fn opportunities(allocator: std.mem.Allocator, paragraph: *const Paragraph, measured: Measurement) ![]Break {
    const text = paragraph.bytes.items;
    const result = try allocator.alloc(Break, text.len + 1);
    errdefer allocator.free(result);
    @memset(result, .none);

    const native = try backend.lineBreaks(allocator, text);
    defer allocator.free(native);
    for (native) |end| {
        if (end != 0 and end <= text.len and measured.clusters[end] and canWrap(paragraph, end))
            result[end] = .soft;
    }
    for (text, 0..) |byte, i| {
        const mode = paragraph.spans.items[paragraph.spanAt(i)].style.values.white_space;
        if (byte == '\n') result[i + 1] = .forced;
        if (ascii.isSpaceOrTab(u8, byte) and mode == .@"break-spaces" and measured.clusters[i + 1])
            result[i + 1] = .soft;
    }
    if (result[text.len] != .forced) result[text.len] = .soft;
    return result;
}

fn canWrap(paragraph: *const Paragraph, end: usize) bool {
    const text = paragraph.bytes.items;
    const mode = paragraph.spans.items[paragraph.spanAt(end - 1)].style.values.white_space;
    if (!mode.wraps()) return false;
    // pre-wrap allows a break after a sequence of preserved spaces.
    return !(mode == .@"pre-wrap" and end < text.len and
        ascii.isSpaceOrTab(u8, text[end - 1]) and ascii.isSpaceOrTab(u8, text[end]));
}

pub fn trimStart(paragraph: *const Paragraph, start: usize) usize {
    var result = start;
    while (result < paragraph.bytes.items.len and collapsible(paragraph, result)) : (result += 1) {}
    return result;
}

pub fn trimEnd(paragraph: *const Paragraph, start: usize, end: usize) usize {
    var result = end;
    while (result > start and collapsible(paragraph, result - 1)) : (result -= 1) {}
    return result;
}

fn collapsible(paragraph: *const Paragraph, index: usize) bool {
    const mode = paragraph.spans.items[paragraph.spanAt(index)].style.values.white_space;
    return ascii.isSpaceOrTab(u8, paragraph.bytes.items[index]) and mode.collapses();
}

fn fitEnd(paragraph: *const Paragraph, start: usize, end: usize) usize {
    var result = trimEnd(paragraph, start, end);
    while (result > start and ascii.isSpaceOrTab(u8, paragraph.bytes.items[result - 1])) {
        const mode = paragraph.spans.items[paragraph.spanAt(result - 1)].style.values.white_space;
        if (mode != .@"pre-wrap") break;
        result -= 1;
    }
    return result;
}

/// Selects a line ending using a greedy wrapping strategy.
///
/// The returned value is a UTF-8 byte offset into `Paragraph.bytes`. If no
/// candidate fits, the first overflowing opportunity is returned so that an
/// unbreakable sequence can overflow instead of being split at an arbitrary
/// position.
pub fn choose(
    paragraph: *const Paragraph,
    measured: Measurement,
    breaks: []const Break,
    start: usize,
    width: f64,
) usize {
    var best: ?usize = null;
    for (start + 1..breaks.len) |end| {
        if (breaks[end] == .none) continue;
        const content_end = if (breaks[end] == .forced) end - 1 else end;
        const fits = measured.width(paragraph, start, fitEnd(paragraph, start, content_end)) <= width;
        if (!fits) return best orelse end;
        best = end;
        if (breaks[end] == .forced) break;
    }
    return best orelse paragraph.bytes.items.len;
}

test "layout: line break computation" {
    const ComputedStyle = @import("../../style/computed/ComputedStyle.zig");
    const allocator = std.testing.allocator;
    const style: ComputedStyle = .{ .values = .{
        .font_size = 16,
        .font_family = .{ .families = &.{.{ .name = "Helvetica" }} },
        .white_space = .normal,
    } };
    const text = "hello world";
    var paragraph: Paragraph = .{};
    defer paragraph.deinit(allocator);
    try paragraph.append(allocator, text, &style);

    const measured = try @import("measure.zig").measure(allocator, &paragraph, .{});
    defer measured.deinit(allocator);
    const breaks = try opportunities(allocator, &paragraph, measured);
    defer allocator.free(breaks);

    try std.testing.expectEqual(Break.soft, breaks[6]);
    try std.testing.expectEqual(@as(usize, 6), choose(
        &paragraph,
        measured,
        breaks,
        0,
        measured.width(&paragraph, 0, 5),
    ));
    try std.testing.expectEqual(@as(usize, 6), choose(&paragraph, measured, breaks, 0, 0));
    try std.testing.expectEqual(text.len, choose(&paragraph, measured, breaks, 0, measured.width(&paragraph, 0, text.len)));
}
