const std = @import("std");
const Url = @import("../../../network/url/Url.zig");
const common = @import("common.zig");

test "network url parser: WPT urltestdata.json" {
    try runParsing("urltestdata.json");
}

test "network url parser: WPT urltestdata-javascript-only.json" {
    try runParsing("urltestdata-javascript-only.json");
}

fn runParsing(comptime name: []const u8) !void {
    const allocator = std.testing.allocator;
    const data = try common.loadFixture(allocator, name);
    defer data.deinit();
    var failed: usize = 0;
    for (data.value.array.items, 0..) |item, i| {
        if (item != .object) continue;
        checkCase(allocator, item) catch |err| {
            if (err == error.OutOfMemory) return err;
            failed += 1;
            std.debug.print(
                "Fixture: {s}, case #{d}, input: {s}: {s}\n",
                .{ name, i, item.object.get("input").?.string, @errorName(err) },
            );
        };
    }
    try std.testing.expectEqual(@as(usize, 0), failed);
}

fn checkCase(allocator: std.mem.Allocator, item: std.json.Value) !void {
    const failure = if (item.object.get("failure")) |value| value.bool else false;
    const url = parseCase(allocator, item) catch |err| {
        if (failure and common.isUrlFailure(err)) return;
        return err;
    };
    defer url.deinit(allocator);
    if (failure) return error.ExpectedFailure;
    var failure_error: ?anyerror = null;
    for (std.meta.tags(common.Property)) |property| {
        const expected = item.object.get(@tagName(property)) orelse continue;
        common.expectProperty(allocator, &url, property, expected.string) catch |err| {
            std.debug.print("  {s}: {s}\n", .{ @tagName(property), @errorName(err) });
            failure_error = err;
        };
    }
    if (failure_error) |err| return err;
}

fn parseCase(allocator: std.mem.Allocator, item: std.json.Value) !Url {
    var base: ?Url = null;
    defer if (base) |url| url.deinit(allocator);
    if (item.object.get("base")) |value| {
        if (value == .string)
            base = try common.parse(allocator, value.string, .{});
    }
    return common.parse(
        allocator,
        item.object.get("input").?.string,
        .{
            .base = if (base) |*url| url else null,
        },
    );
}
