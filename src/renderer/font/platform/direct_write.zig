const std = @import("std");
const dw = @import("dwrite_zig");
pub const Font = @import("direct_write/Font.zig");
pub const Family = @import("direct_write/Family.zig");
pub const shape = @import("direct_write/shaping.zig").shape;

/// Returns Unicode line-breaking opportunities as UTF-8 byte offsets.
pub fn lineBreaks(allocator: std.mem.Allocator, text: []const u8) ![]usize {
    if (text.len == 0) return allocator.alloc(usize, 0);
    const factory = try dw.Factory.init(dw.raw.DWRITE_FACTORY_TYPE_SHARED);
    defer factory.deinit();
    const format = try factory.createTextFormat(allocator, .{
        .family_name = "Segoe UI",
        .size = 12,
        .locale = "en-us",
    });
    defer format.deinit();
    const layout = try factory.createTextLayout(allocator, text, format, 0, 0);
    defer layout.deinit();
    const clusters = try layout.getClusterMetrics(allocator);
    defer allocator.free(clusters);

    var result: std.ArrayList(usize) = .empty;
    errdefer result.deinit(allocator);
    var iterator = std.unicode.Utf8View.initUnchecked(text).iterator();

    var units: usize = 0;
    var end: usize = 0;
    for (clusters) |cluster| {
        end += cluster.length;
        while (units < end) {
            const bytes = iterator.nextCodepointSlice() orelse return error.InvalidStringIndex;
            units += if (bytes.len == 4) @as(usize, 2) else 1;
        }
        if (units != end) return error.InvalidStringIndex;
        if (cluster.can_wrap_line_after) try result.append(allocator, iterator.i);
    }

    return result.toOwnedSlice(allocator);
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "direct_write lineBreaks: UTF-8 offsets" {
    const allocator = std.testing.allocator;
    const breaks = try lineBreaks(allocator, "😀 😀");
    defer allocator.free(breaks);

    try std.testing.expectEqualSlices(usize, &.{ 5, 9 }, breaks);
}
