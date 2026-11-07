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
        common.expectHostCase(allocator, item) catch |err| {
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
