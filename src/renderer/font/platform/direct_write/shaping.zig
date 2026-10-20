const std = @import("std");
const dw = @import("dwrite_zig");
const Font = @import("Font.zig");
const ShapedText = @import("../../ShapedText.zig");

pub fn shape(allocator: std.mem.Allocator, text: []const u8, font: Font, direction: ShapedText.Direction) !ShapedText {
    const wide = try directedText(allocator, text, direction);
    defer allocator.free(wide);
    const offsets = try sourceOffsets(allocator, text, wide.len);
    defer allocator.free(offsets);

    const factory = try dw.Factory.init(dw.raw.DWRITE_FACTORY_TYPE_SHARED);
    defer factory.deinit();
    const collection = try factory.getSystemFontCollection(false);
    defer collection.deinit();
    const layout = try createLayout(allocator, factory, collection, wide, font, direction);
    defer layout.deinit();

    const metrics = try layout.getMetrics();
    const runs = try collectRuns(allocator, layout, collection, offsets, font.size);

    return shapedText(runs, if (font.size == 0) 0 else metrics.widthIncludingTrailingWhitespace);
}

fn directedText(allocator: std.mem.Allocator, text: []const u8, direction: ShapedText.Direction) ![]u16 {
    const utf16 = try std.unicode.utf8ToUtf16LeAlloc(allocator, text);
    defer allocator.free(utf16);
    const length = std.math.add(u32, std.math.cast(u32, utf16.len) orelse return error.InputTooLong, 2) catch return error.InputTooLong;
    // The caller already resolved direction, here just match the api.
    const wide = try allocator.alloc(u16, length);
    wide[0] = if (direction == .ltr) 0x202d else 0x202e;
    @memcpy(wide[1 .. wide.len - 1], utf16);
    wide[wide.len - 1] = 0x202c;

    return wide;
}

fn createLayout(
    allocator: std.mem.Allocator,
    factory: dw.Factory,
    collection: dw.FontCollection,
    text: []const u16,
    font: Font,
    direction: ShapedText.Direction,
) !dw.TextLayout {
    const format = try textFormat(allocator, factory, collection, font, direction);
    defer format.deinit();

    return factory.createTextLayoutUtf16(text, format, 0, 0);
}

fn textFormat(
    allocator: std.mem.Allocator,
    factory: dw.Factory,
    collection: dw.FontCollection,
    font: Font,
    direction: ShapedText.Direction,
) !dw.TextFormat {
    const name = try font.familyName(allocator);
    defer allocator.free(name);
    const format = try factory.createTextFormat(allocator, .{
        .family_name = name,
        .collection = collection,
        .weight = font.descriptor.getWeight(),
        .style = font.descriptor.getStyle(),
        .stretch = font.descriptor.getStretch(),
        .size = if (font.size == 0) 1 else @floatCast(font.size),
        .locale = "en-us",
    });
    errdefer format.deinit();
    try format.setWordWrapping(dw.raw.DWRITE_WORD_WRAPPING_NO_WRAP);
    try format.setReadingDirection(if (direction == .ltr) dw.raw.DWRITE_READING_DIRECTION_LEFT_TO_RIGHT else dw.raw.DWRITE_READING_DIRECTION_RIGHT_TO_LEFT);
    try format.setTextAlignment(if (direction == .ltr) dw.raw.DWRITE_TEXT_ALIGNMENT_LEADING else dw.raw.DWRITE_TEXT_ALIGNMENT_TRAILING);

    return format;
}

fn collectRuns(
    allocator: std.mem.Allocator,
    layout: dw.TextLayout,
    collection: dw.FontCollection,
    offsets: []const usize,
    size: f64,
) ![]ShapedText.Run {
    const native_runs = try layout.getGlyphRuns(allocator);
    defer {
        for (native_runs) |run| run.deinit(allocator);
        allocator.free(native_runs);
    }
    var runs: std.ArrayList(ShapedText.Run) = .empty;
    defer runs.deinit(allocator);
    errdefer for (runs.items) |run| run.deinit(allocator);

    var baseline: ?f64 = null;
    for (native_runs) |native| {
        const run = try collectRun(allocator, native, collection, offsets, size, &baseline) orelse continue;
        errdefer run.deinit(allocator);
        try runs.append(allocator, run);
    }
    // The renderer consumes runs in visual order, with Y increasing upward.
    std.mem.sort(ShapedText.Run, runs.items, {}, visualOrder);

    return runs.toOwnedSlice(allocator);
}

fn visualOrder(_: void, a: ShapedText.Run, b: ShapedText.Run) bool {
    return a.glyphs[0].position[0] < b.glyphs[0].position[0];
}

fn shapedText(runs: []ShapedText.Run, width: f64) ShapedText {
    var result: ShapedText = .{
        .runs = runs,
        .width = width,
        .ascent = 0,
        .descent = 0,
        .leading = 0,
    };
    for (runs) |run| {
        const metrics = run.font.metrics();
        result.ascent = @max(result.ascent, metrics.ascent);
        result.descent = @max(result.descent, metrics.descent);
        result.leading = @max(result.leading, metrics.leading);
    }

    return result;
}

fn collectRun(
    allocator: std.mem.Allocator,
    native: dw.GlyphRun,
    collection: dw.FontCollection,
    offsets: []const usize,
    size: f64,
    baseline: *?f64,
) !?ShapedText.Run {
    const range = try textRange(native, offsets) orelse return null;
    const glyphs = try collectGlyphs(allocator, native, offsets, size, baseline) orelse return null;
    errdefer allocator.free(glyphs);

    return .{
        .font = try runFont(native, collection, size),
        .direction = if (native.isRightToLeft()) .rtl else .ltr,
        .glyphs = glyphs,
        .text_range = .{ .start = range.start, .end = range.end },
        .text_matrix = .{
            .{ 1, 0 },
            .{ 0, 1 },
            .{ 0, 0 },
        },
    };
}

const TextRange = struct { start: usize, end: usize };

fn textRange(native: dw.GlyphRun, offsets: []const usize) !?TextRange {
    const start: usize = native.text_position;
    const end = start + native.cluster_map.len;
    if (end >= offsets.len) return error.InvalidStringIndex;

    const real_end = offsets.len - 2;
    if (native.glyph_indices.len == 0 or end <= 1 or start >= real_end) return null;

    return .{
        .start = offsets[@max(start, 1)],
        .end = offsets[@min(end, real_end)],
    };
}

fn collectGlyphs(
    allocator: std.mem.Allocator,
    native: dw.GlyphRun,
    offsets: []const usize,
    size: f64,
    baseline: *?f64,
) !?[]ShapedText.Glyph {
    const indices = try native.getStringIndices(allocator);
    defer allocator.free(indices);
    const real_end = offsets.len - 2;
    const count = sourceGlyphCount(indices, real_end);
    if (count == 0) return null;

    const positions = try native.getPositions(allocator);
    defer allocator.free(positions);
    const glyphs = try allocator.alloc(ShapedText.Glyph, count);
    errdefer allocator.free(glyphs);

    if (baseline.* == null) baseline.* = native.baseline.y;
    var output: usize = 0;
    for (indices, native.glyph_indices, positions, native.glyph_advances) |unit, id, position, advance| {
        // Remove only the direction controls introduced by shape().
        if (unit < 1 or unit >= real_end) continue;
        glyphs[output] = glyph(id, offsets[unit], position, advance, size, baseline.*.?);
        output += 1;
    }
    if (native.isRightToLeft()) std.mem.reverse(ShapedText.Glyph, glyphs);

    return glyphs;
}

fn sourceGlyphCount(indices: []const u32, end: usize) usize {
    var count: usize = 0;
    for (indices) |unit| {
        if (unit >= 1 and unit < end) count += 1;
    }

    return count;
}

fn glyph(
    id: u16,
    cluster: usize,
    position: dw.GlyphRun.Point,
    advance: f32,
    size: f64,
    baseline: f64,
) ShapedText.Glyph {
    return .{
        .id = id,
        .cluster = cluster,
        .position = if (size == 0) .{ 0, 0 } else .{ position.x, baseline - position.y },
        .advance = if (size == 0) .{ 0, 0 } else .{ advance, 0 },
    };
}

fn runFont(native: dw.GlyphRun, collection: dw.FontCollection, size: f64) !Font {
    const descriptor = try collection.getFontFromFontFace(native.font_face);
    return .{
        .native = native.font_face.retain(),
        .descriptor = descriptor,
        .size = if (size == 0) 0 else native.font_em_size,
    };
}

/// Includes the direction controls, both halves of a surrogate map to one byte offset.
fn sourceOffsets(allocator: std.mem.Allocator, text: []const u8, length: usize) ![]usize {
    const offsets = try allocator.alloc(usize, length + 1);
    offsets[0] = 0;
    offsets[length - 1] = text.len;
    offsets[length] = text.len;
    var iterator = std.unicode.Utf8View.initUnchecked(text).iterator();
    var unit: usize = 1;
    while (iterator.nextCodepointSlice()) |bytes| {
        offsets[unit] = iterator.i - bytes.len;
        unit += 1;
        if (bytes.len == 4) {
            offsets[unit] = iterator.i - bytes.len;
            unit += 1;
        }
    }
    return offsets;
}
