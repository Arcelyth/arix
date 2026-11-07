const std = @import("std");
const Parser = @import("../../../network/url/Parser.zig");
const Url = @import("../../../network/url/Url.zig");
const common = @import("common.zig");

test "network url parser: WPT protocol setters" {
    try runSetters(.protocol, .scheme_start);
}

test "network url parser: WPT host setters" {
    try runSetters(.host, .host);
}

test "network url parser: WPT hostname setters" {
    try runSetters(.hostname, .hostname);
}

test "network url parser: WPT port setters" {
    try runSetters(.port, .port);
}

test "network url parser: WPT pathname setters" {
    try runSetters(.pathname, .path_start);
}

test "network url parser: WPT search setters" {
    try runSetters(.search, .query);
}

test "network url parser: WPT hash setters" {
    try runSetters(.hash, .fragment);
}

fn runSetters(comptime property: common.Property, comptime state: Parser.State) !void {
    const allocator = std.testing.allocator;
    const fixture = try common.loadFixture(allocator, "setters_tests.json");
    defer fixture.deinit();
    var failed: usize = 0;
    for (fixture.value.object.get(@tagName(property)).?.array.items, 0..) |item, i| {
        checkSetter(allocator, item, property, state) catch |err| {
            if (err == error.OutOfMemory) return err;
            failed += 1;
            std.debug.print(
                "WPT {s} setter #{d}: {s}\n",
                .{ @tagName(property), i, @errorName(err) },
            );
        };
    }
    try std.testing.expectEqual(@as(usize, 0), failed);
}

fn checkSetter(
    allocator: std.mem.Allocator,
    item: std.json.Value,
    comptime property: common.Property,
    comptime state: Parser.State,
) !void {
    var url = try common.parse(allocator, item.object.get("href").?.string, .{});
    defer url.deinit(allocator);
    const value = item.object.get("new_value").?.string;
    // The protocol setter passes its value followed by ':'.
    const protocol: ?[]u8 = if (property == .protocol) try std.fmt.allocPrint(allocator, "{s}:", .{value}) else null;
    defer if (protocol) |text| allocator.free(text);

    var input: []const u8 = protocol orelse value;
    if ((property == .search and std.mem.startsWith(u8, input, "?")) or
        (property == .hash and std.mem.startsWith(u8, input, "#"))) input = input[1..];
    var parser = Parser.init(allocator);
    defer parser.deinit();
    if (try prepareSetter(allocator, &url, property, value)) {
        parser.parseExisting(input, .{ .state_override = state }, &url) catch |err| {
            if (!common.isUrlFailure(err) and err != error.InvalidScheme and err != error.HostnameContainsPort) return err;
        };
    }
    var expected = item.object.get("expected").?.object.iterator();
    while (expected.next()) |field| {
        try common.expectProperty(
            allocator,
            &url,
            std.meta.stringToEnum(common.Property, field.key_ptr.*).?,
            field.value_ptr.string,
        );
    }
}

// Performs the URL setter's steps before it calls the basic parser.
fn prepareSetter(
    allocator: std.mem.Allocator,
    url: *Url,
    comptime property: common.Property,
    input: []const u8,
) !bool {
    if ((property == .host or property == .hostname or property == .pathname) and
        url.opaque_path)
        return false;
    if (property == .port and
        (url.opaque_path or url.parsed.host == null or url.parsed.host.?.len == 0 or std.mem.eql(u8, url.scheme(), "file")))
        return false;
    if (property == .protocol or property == .host or property == .hostname or
        (property == .port and input.len != 0))
        return true;

    var parser = Parser.init(allocator);
    defer parser.deinit();
    parser.output = std.ArrayList(u8).fromOwnedSlice(url.source);
    parser.parsed = url.parsed;
    parser.opaque_path = url.opaque_path;
    url.* = .empty;
    switch (property) {
        .port => try parser.setPort(null),
        .pathname => try parser.setPath(""),
        .search => if (input.len == 0) try parser.removeQuery() else try parser.setQuery(""),
        .hash => if (input.len == 0) try parser.removeFragment() else try parser.setFragment(""),
        else => unreachable,
    }
    url.* = .{
        .source = try parser.output.toOwnedSlice(allocator),
        .parsed = parser.parsed,
        .opaque_path = parser.opaque_path,
    };
    return property == .pathname or input.len != 0;
}
