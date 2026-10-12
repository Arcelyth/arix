const std = @import("std");
const core = @import("core_foundation_zig");
const cf = core.core_foundation;
const ct = core.core_text;
const Font = @import("Font.zig");
const ShapedText = @import("../../ShapedText.zig");
const Direction = ShapedText.Direction;

pub fn shape(
    allocator: std.mem.Allocator,
    text: []const u8,
    font: Font,
    direction: Direction,
) !ShapedText {
    const string = try attributedString(text, font, direction);
    defer string.deinit();
    const line = ct.CTLine.init(string);
    defer line.deinit();
    const offsets = try sourceOffsets(allocator, text, string.len());
    defer allocator.free(offsets);

    const runs = try collectRuns(allocator, line, offsets, font.size);
    var result: ShapedText = .{
        .runs = runs,
        .width = 0,
        .ascent = 0,
        .descent = 0,
        .leading = 0,
    };
    if (font.size != 0)
        result.width = line.getTypographicBounds(&result.ascent, &result.descent, &result.leading);
    return result;
}

fn attributedString(text: []const u8, font: Font, direction: Direction) !cf.CFAttributeString {
    const writing_direction: i32 = switch (direction) {
        .ltr => core.raw.kCTWritingDirectionLeftToRight,
        .rtl => core.raw.kCTWritingDirectionRightToLeft,
    };
    // Apply the caller's resolved run direction.
    // https://developer.apple.com/documentation/coretext/kctwritingdirectionattributename
    const number = try cf.CFNumber.init(writing_direction | core.raw.kCTWritingDirectionOverride);
    defer number.deinit();
    const directions = try cf.CFArray(cf.CFNumber).init(&.{number});
    defer directions.deinit();
    const attributes = try cf.CFAttributeString.Attributes.init(&.{
        .{ .key = .fromRef(core.raw.kCTFontAttributeName), .value = font.native.asCFTypeRef() },
        .{ .key = .fromRef(core.raw.kCTWritingDirectionAttributeName), .value = directions.asCFTypeRef() },
    });
    defer attributes.deinit();
    return cf.CFAttributeString.initWithAttributes(text, attributes);
}

/// Map each UTF-16 code unit to its source UTF-8 byte offset.
fn sourceOffsets(allocator: std.mem.Allocator, text: []const u8, utf16_len: usize) ![]usize {
    const offsets = try allocator.alloc(usize, utf16_len);
    var iterator = std.unicode.Utf8View.initUnchecked(text).iterator();
    var unit: usize = 0;
    while (iterator.nextCodepointSlice()) |bytes| {
        const byte_offset = iterator.i - bytes.len;
        offsets[unit] = byte_offset;
        unit += 1;
        // Four-byte UTF-8 code points occupy a UTF-16 surrogate pair.
        if (bytes.len == 4) {
            offsets[unit] = byte_offset;
            unit += 1;
        }
    }
    return offsets;
}

fn collectRuns(
    allocator: std.mem.Allocator,
    line: ct.CTLine,
    offsets: []const usize,
    size: f64,
) ![]ShapedText.Run {
    const native_runs = line.getGlyphRuns();
    const runs = try allocator.alloc(ShapedText.Run, native_runs.len());
    errdefer allocator.free(runs);
    var initialized: usize = 0;
    errdefer for (runs[0..initialized]) |run| run.deinit(allocator);
    for (runs, 0..) |*run, i| {
        run.* = try collectRun(allocator, native_runs.get(i).?, offsets, size);
        initialized += 1;
    }
    return runs;
}

fn collectRun(
    allocator: std.mem.Allocator,
    run: ct.CTRun,
    offsets: []const usize,
    size: f64,
) !ShapedText.Run {
    const font = try runFont(run, size);
    errdefer font.deinit();
    const glyphs = try collectGlyphs(allocator, run, offsets, size);
    const matrix = run.getTextMatrix();

    return .{
        .font = font,
        .direction = if (run.getStatus() & core.raw.kCTRunStatusRightToLeft != 0) .rtl else .ltr,
        .glyphs = glyphs,
        .text_matrix = .{
            .{ matrix.a, matrix.b },
            .{ matrix.c, matrix.d },
            .{ matrix.tx, matrix.ty },
        },
    };
}

fn runFont(run: ct.CTRun, size: f64) !Font {
    const ref = run.getAttributes().get(.fromRef(core.raw.kCTFontAttributeName)) orelse return error.MissingRunFont;
    const native = ct.CTFont.fromRef(@ptrCast(@alignCast(ref)));

    return .{
        .native = native.retain(),
        .size = if (size == 0) 0 else native.getSize(),
    };
}

fn collectGlyphs(
    allocator: std.mem.Allocator,
    run: ct.CTRun,
    offsets: []const usize,
    size: f64,
) ![]ShapedText.Glyph {
    const ids = try run.getGlyphs(allocator);
    defer allocator.free(ids);
    const positions = try run.getPositions(allocator);
    defer allocator.free(positions);
    const advances = try run.getAdvances(allocator);
    defer allocator.free(advances);
    const indices = try run.getStringIndices(allocator);
    defer allocator.free(indices);
    const glyphs = try allocator.alloc(ShapedText.Glyph, ids.len);
    errdefer allocator.free(glyphs);

    for (glyphs, ids, positions, advances, indices) |*glyph, id, position, advance, index| {
        const unit = cf.CFIndex.toUsize(index) orelse return error.InvalidStringIndex;
        if (unit >= offsets.len) return error.InvalidStringIndex;
        glyph.* = .{
            .id = id,
            .cluster = offsets[unit],
            .position = if (size == 0) .{ 0, 0 } else .{ position.x, position.y },
            .advance = if (size == 0) .{ 0, 0 } else .{ advance.width, advance.height },
        };
    }
    return glyphs;
}
