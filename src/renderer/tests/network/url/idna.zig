const std = @import("std");
const common = @import("common.zig");

test "network url parser: WPT IdnaTestV2.json" {
    try runIdnaParsing("IdnaTestV2.json");
}

test "network url parser: WPT IdnaTestV2-removed.json" {
    try runIdnaParsing("IdnaTestV2-removed.json");
}

fn runIdnaParsing(comptime name: []const u8) !void {
    const allocator = std.testing.allocator;
    const data = try common.loadFixture(allocator, name);
    defer data.deinit();

    var failed: usize = 0;
    for (data.value.array.items, 0..) |item, i| {
        if (item != .object) continue;
        const input = item.object.get("input").?.string;
        // WPT excludes this row: https:///x parses with host "x", not an empty host.
        if (input.len == 0) continue;
        checkIdnaCase(allocator, item) catch |err| {
            if (err == error.OutOfMemory) return err;
            failed += 1;
            std.debug.print(
                "Fixture: {s}, case #{d}, input: {s}: {s}\n",
                .{ name, i, input, @errorName(err) },
            );
        };
    }
    try std.testing.expectEqual(@as(usize, 0), failed);
}

fn checkIdnaCase(allocator: std.mem.Allocator, item: std.json.Value) !void {
    const input = item.object.get("input").?.string;
    const expected = item.object.get("output").?;
    const text = try std.fmt.allocPrint(allocator, "https://{s}/x", .{input});
    defer allocator.free(text);

    const url = common.parse(allocator, text, .{}) catch |err| {
        if (expected == .null and common.isUrlFailure(err)) return;
        return err;
    };
    defer url.deinit(allocator);
    if (expected == .null) return error.ExpectedFailure;

    try common.expectProperty(allocator, &url, .host, expected.string);
    try common.expectProperty(allocator, &url, .hostname, expected.string);
    try common.expectProperty(allocator, &url, .pathname, "/x");
    const href = try std.fmt.allocPrint(allocator, "https://{s}/x", .{expected.string});
    defer allocator.free(href);
    try common.expectProperty(allocator, &url, .href, href);
}
