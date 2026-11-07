const std = @import("std");
const encodings = @import("../../../encoding/encoding.zig");
const common = @import("common.zig");

test "network url parser: WPT percent-encoding.json" {
    const allocator = std.testing.allocator;
    const data = try common.loadFixture(allocator, "percent-encoding.json");
    defer data.deinit();
    var failed: usize = 0;
    for (data.value.array.items, 0..) |item, i| {
        if (item != .object) continue;
        var outputs = item.object.get("output").?.object.iterator();
        while (outputs.next()) |output| {
            checkCase(allocator, item, output.key_ptr.*, output.value_ptr.string) catch |err| {
                if (err == error.OutOfMemory) return err;
                failed += 1;
                std.debug.print(
                    "Fixture: percent-encoding.json, case #{d}, encoding: {s}: {s}\n",
                    .{ i, output.key_ptr.*, @errorName(err) },
                );
            };
        }
    }
    try std.testing.expectEqual(@as(usize, 0), failed);
}

fn checkCase(allocator: std.mem.Allocator, item: std.json.Value, label: []const u8, expected: []const u8) !void {
    const input = item.object.get("input").?.string;
    const encoding = encodings.nameToEncoding(label) orelse return error.UnknownTestEncoding;
    const text = try std.fmt.allocPrint(
        allocator,
        "https://doesnotmatter.invalid/?{s}#{s}",
        .{ input, input },
    );
    defer allocator.free(text);
    const url = try common.parse(allocator, text, .{ .encoding = encoding });
    defer url.deinit(allocator);

    try std.testing.expectEqualStrings(expected, url.query().?);
    const utf8 = item.object.get("output").?.object.get("utf-8").?.string;
    try std.testing.expectEqualStrings(utf8, url.fragment().?);
}
