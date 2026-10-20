const std = @import("std");
const hb = @import("harfbuzz_zig");
const unibreak = @import("unibreak_zig");
const Font = @import("Font.zig");
const Fallback = @import("Fallback.zig");
const utils = @import("utils.zig");
const ShapedText = @import("../../ShapedText.zig");
const Script = hb.raw.hb_script_t;

const Segment = struct {
    start: usize,
    end: usize,
    script: Script,
    font: Font,
};

pub fn shape(
    allocator: std.mem.Allocator,
    text: []const u8,
    font: Font,
    direction: ShapedText.Direction,
) !ShapedText {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    if (text.len > std.math.maxInt(i32)) return error.InputTooLong;

    var result: ShapedText = .{
        .runs = undefined,
        .width = 0,
        .ascent = 0,
        .descent = 0,
        .leading = 0,
    };
    const segments = try itemize(allocator, text, font);
    defer {
        for (segments) |segment| segment.font.deinit();
        allocator.free(segments);
    }
    result.runs = try allocator.alloc(ShapedText.Run, segments.len);
    errdefer allocator.free(result.runs);

    var initialized: usize = 0;
    errdefer for (result.runs[0..initialized]) |run| run.deinit(allocator);
    const buffer = try hb.Buffer.init();
    defer buffer.deinit();
    for (result.runs, 0..) |*run, i| {
        const segment = segments[if (direction == .ltr) i else segments.len - 1 - i];
        run.* = try shapeRun(allocator, buffer, text, segment, direction, &result.width);
        initialized += 1;
        const metrics = run.font.metrics();
        result.ascent = @max(result.ascent, metrics.ascent);
        result.descent = @max(result.descent, metrics.descent);
        result.leading = @max(result.leading, metrics.leading);
    }

    return result;
}

fn itemize(allocator: std.mem.Allocator, text: []const u8, font: Font) ![]Segment {
    const boundaries = try unibreak.graphemeBreaks(allocator, text);
    defer allocator.free(boundaries);
    const scripts = try allocator.alloc(Script, boundaries.len - 1);
    defer allocator.free(scripts);

    var previous: Script = hb.raw.HB_SCRIPT_COMMON;
    for (scripts, 0..) |*script, i| {
        script.* = clusterScript(text[boundaries[i]..boundaries[i + 1]]);
        if (neutral(script.*)) script.* = previous else previous = script.*;
    }
    var next: Script = hb.raw.HB_SCRIPT_COMMON;
    var i = scripts.len;
    while (i != 0) {
        i -= 1;
        if (neutral(scripts[i])) scripts[i] = next else next = scripts[i];
    }

    var fallback: Fallback = .{ .base = font };
    defer fallback.deinit(allocator);
    var segments: std.ArrayList(Segment) = .empty;
    errdefer {
        for (segments.items) |segment| segment.font.deinit();
        segments.deinit(allocator);
    }

    for (scripts, 0..) |script, index| {
        const start = boundaries[index];
        const end = boundaries[index + 1];
        const selected = try fallback.forText(allocator, text[start..end]);
        if (segments.items.len != 0) {
            const last = &segments.items[segments.items.len - 1];
            if (last.script == script and try utils.sameFace(last.font.descriptor, selected.descriptor)) {
                last.end = end;
                continue;
            }
        }
        try segments.ensureUnusedCapacity(allocator, 1);
        segments.appendAssumeCapacity(.{ .start = start, .end = end, .script = script, .font = selected.retain() });
    }

    return segments.toOwnedSlice(allocator);
}

fn clusterScript(text: []const u8) Script {
    var iterator = std.unicode.Utf8View.initUnchecked(text).iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        const script = hb.unicode.script(codepoint);
        if (!neutral(script)) return script;
    }
    return hb.raw.HB_SCRIPT_COMMON;
}

inline fn neutral(script: Script) bool {
    return script == hb.raw.HB_SCRIPT_COMMON or script == hb.raw.HB_SCRIPT_INHERITED or script == hb.raw.HB_SCRIPT_UNKNOWN;
}

fn shapeRun(allocator: std.mem.Allocator, buffer: hb.Buffer, text: []const u8, segment: Segment, direction: ShapedText.Direction, pen: *f64) !ShapedText.Run {
    const native = segment.font.shapingFont();
    const shaped = try buffer.shape(native, text, segment.start, segment.end, if (direction == .ltr) .ltr else .rtl, segment.script);
    const scale = segment.font.size / @as(f64, @floatFromInt(native.units_per_em));
    const glyphs = try allocator.alloc(ShapedText.Glyph, shaped.infos.len);
    errdefer allocator.free(glyphs);

    var y: f64 = 0;
    for (glyphs, shaped.infos, shaped.positions) |*glyph, info, position| {
        if (info.cluster < segment.start or info.cluster >= segment.end) return error.InvalidStringIndex;
        const advance = .{
            @as(f64, @floatFromInt(position.x_advance)) * scale,
            @as(f64, @floatFromInt(position.y_advance)) * scale,
        };

        glyph.* = .{
            .id = std.math.cast(u16, info.codepoint) orelse return error.InvalidGlyphIndex,
            .cluster = info.cluster,
            .position = .{
                pen.* + @as(f64, @floatFromInt(position.x_offset)) * scale,
                y + @as(f64, @floatFromInt(position.y_offset)) * scale,
            },
            .advance = advance,
        };
        pen.* += advance[0];
        y += advance[1];
    }

    return .{
        .font = segment.font.retain(),
        .direction = direction,
        .glyphs = glyphs,
        .text_range = .{
            .start = segment.start,
            .end = segment.end,
        },
        .text_matrix = .{
            .{ 1, 0 },
            .{ 0, 1 },
            .{ 0, 0 },
        },
    };
}
