//! https://url.spec.whatwg.org/#url-representation
const Url = @This();
const std = @import("std");
const Host = @import("host.zig").Host;
const Parser = @import("Parser.zig");
const form = @import("form_urlencoded.zig");

pub const Component = struct {
    begin: usize = 0,
    len: usize = 0,

    pub inline fn fromBounds(begin: usize, end_offset: usize) Component {
        return .{
            .begin = begin,
            .len = end_offset - begin,
        };
    }

    pub inline fn end(self: *const Component) usize {
        return self.begin + self.len;
    }

    /// Returns this component's slice from the `source` full URL string.
    pub inline fn slice(self: *const Component, source: []const u8) []const u8 {
        return source[self.begin..self.end()];
    }
};

pub const Parsed = struct {
    scheme: Component = .{},
    username: ?Component = null,
    password: ?Component = null,
    host: ?Component = null,
    port: ?Component = null,
    path: Component = .{},
    query: ?Component = null,
    fragment: ?Component = null,
};

/// Full URL string.
source: []u8,
/// Components from spec.
parsed: Parsed = .{},
opaque_path: bool = false,

pub const empty: Url = .{ .source = &.{} };

pub fn deinit(self: Url, allocator: std.mem.Allocator) void {
    allocator.free(self.source);
}

pub fn sliceC(self: *const Url, c: Component) []const u8 {
    return c.slice(self.source);
}

pub fn scheme(self: *const Url) []const u8 {
    return self.sliceC(self.parsed.scheme);
}

pub fn username(self: *const Url) []const u8 {
    return self.sliceC(self.parsed.username orelse return "");
}

pub fn password(self: *const Url) ?[]const u8 {
    return self.sliceC(self.parsed.password orelse return null);
}

pub fn host(self: *const Url) ?Host {
    return Host.fromSlice(self.sliceC(self.parsed.host orelse return null), !self.isSpecial());
}

/// Returns the explicit port as a number, or null if absent.
pub fn port(self: *const Url) ?u16 {
    const text = self.sliceC(self.parsed.port orelse return null);
    return std.fmt.parseInt(u16, text, 10) catch unreachable;
}

pub fn path(self: *const Url) []const u8 {
    return self.sliceC(self.parsed.path);
}

pub fn query(self: *const Url) ?[]const u8 {
    return self.sliceC(self.parsed.query orelse return null);
}

pub fn fragment(self: *const Url) ?[]const u8 {
    return self.sliceC(self.parsed.fragment orelse return null);
}

/// Returns the serialized origin, or "null" for an opaque origin.
/// https://url.spec.whatwg.org/#concept-url-origin
pub fn serializeOrigin(self: *const Url, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    const protocol = self.scheme();
    if (std.mem.eql(u8, protocol, "blob")) {
        var parser = Parser.init(allocator);
        defer parser.deinit();
        const nested = parser.parse(self.path(), .{}) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return allocator.dupe(u8, "null");
        };
        defer nested.deinit(allocator);
        if (std.mem.eql(u8, nested.scheme(), "http") or
            std.mem.eql(u8, nested.scheme(), "https") or
            std.mem.eql(u8, nested.scheme(), "file"))
            return nested.serializeOrigin(allocator);
        return allocator.dupe(u8, "null");
    }
    // ftp, http, https, ws, wss and file.
    if (self.isSpecial() and !std.mem.eql(u8, protocol, "file")) {
        const hostname = self.parsed.host.?;
        const end = if (self.parsed.port) |value| value.end() else hostname.end();
        return std.fmt.allocPrint(
            allocator,
            "{s}://{s}",
            .{ protocol, self.source[hostname.begin..end] },
        );
    }
    return allocator.dupe(u8, "null");
}

/// Returns the query as serialized form data.
/// https://url.spec.whatwg.org/#urlsearchparams-stringification-behavior
pub fn serializeSearchParams(self: *const Url, allocator: std.mem.Allocator) ![]u8 {
    const pairs = try form.parse(allocator, self.query() orelse "");
    defer {
        for (pairs) |pair| pair.deinit(allocator);
        allocator.free(pairs);
    }

    return form.serialize(allocator, pairs, .utf8);
}

/// https://url.spec.whatwg.org/#special-scheme
pub const special_scheme = std.StaticStringMap(?u16).initComptime(.{
    .{ "ftp", 21 },    .{ "file", null }, .{ "http", 80 },
    .{ "https", 443 }, .{ "ws", 80 },     .{ "wss", 443 },
});

pub fn isSpecial(self: *const Url) bool {
    return special_scheme.has(self.scheme());
}

test "network url: check url's each component" {
    var source = "https://user:pass@example.org:8080/path?q=1#top".*;
    // FIXME: Replace this when parse func has been implemented.
    var url: Url = .{
        .source = &source,
        .parsed = .{
            .scheme = .{ .begin = 0, .len = 5 },
            .username = Component.fromBounds(8, 12),
            .password = Component.fromBounds(13, 17),
            .host = Component.fromBounds(18, 29),
            .port = Component.fromBounds(30, 34),
            .path = Component.fromBounds(34, 39),
            .query = Component.fromBounds(40, 43),
            .fragment = Component.fromBounds(44, 47),
        },
    };

    try std.testing.expectEqualStrings("https", url.scheme());
    try std.testing.expect(url.isSpecial());
    try std.testing.expectEqualStrings("user", url.username());
    try std.testing.expectEqualStrings("pass", url.password().?);
    try std.testing.expectEqualStrings("example.org", url.host().?.domain);
    try std.testing.expectEqual(@as(?u16, 8080), url.port());
    try std.testing.expectEqualStrings("/path", url.path());
    try std.testing.expectEqualStrings("q=1", url.query().?);
    try std.testing.expectEqualStrings("top", url.fragment().?);
}
