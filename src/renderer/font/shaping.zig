const std = @import("std");
const backend = @import("platform.zig").backend;
pub const ShapedText = @import("ShapedText.zig");
pub const Direction = ShapedText.Direction;

pub fn shape(
    allocator: std.mem.Allocator,
    text: []const u8,
    font: backend.Font,
    direction: Direction,
) !ShapedText {
    return backend.shape(allocator, text, font, direction);
}

test "font shaping: positions, advances and owned font" {
    // FIXME: Remove this when implement other platform.
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    const Font = @import("platform.zig").backend.Font;
    const shaping = @import("shaping.zig");
    const allocator = std.testing.allocator;

    const result = blk: {
        const font = try Font.initWithName("Helvetica", 16);
        defer font.deinit();
        break :blk try shaping.shape(allocator, "ABC", font, .ltr);
    };
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.runs.len);

    const run = result.runs[0];
    try std.testing.expectEqual(.ltr, run.direction);
    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expect(result.width > 0 and result.ascent > 0 and result.descent >= 0);

    for (run.glyphs, 0..) |glyph, i| {
        try std.testing.expect(glyph.id != 0);
        try std.testing.expectEqual(i, glyph.cluster);
        try std.testing.expect(glyph.advance[0] > 0);
    }
    const last = run.glyphs[2];
    try std.testing.expectApproxEqAbs(
        result.width,
        last.position[0] + last.advance[0],
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        run.glyphs[0].advance[0],
        run.glyphs[1].position[0],
        0.001,
    );

    const name = try run.font.postScriptName(allocator);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("Helvetica", name);
}
