const std = @import("std");
const Parser = @import("../../../network/url/Parser.zig");
const Url = @import("../../../network/url/Url.zig");
const ParserError = @import("../../../network/url/error.zig").ParserError;

const test_data_dir = "../../wpt/url/resources/";

/// Reads a WPT JSON file and replaces lone surrogates for URL input.
pub fn loadFixture(allocator: std.mem.Allocator, comptime name: []const u8) !std.json.Parsed(std.json.Value) {
    const text = try allocator.dupe(u8, @embedFile(test_data_dir ++ name));
    defer allocator.free(text);
    replaceSurrogates(text);
    return std.json.parseFromSlice(std.json.Value, allocator, text, .{ .allocate = .alloc_always });
}

pub fn parse(allocator: std.mem.Allocator, input: []const u8, opts: Parser.ParseOpts) !Url {
    var parser = Parser.init(allocator, input);
    defer parser.deinit();
    return parser.parseUrl(opts);
}

pub fn isUrlFailure(err: anyerror) bool {
    return std.meta.stringToEnum(ParserError, @errorName(err)) != null;
}

pub const Property = enum {
    href,
    protocol,
    username,
    password,
    host,
    hostname,
    port,
    pathname,
    search,
    hash,
    origin,
    searchParams,
};

/// Reads the string properties asserted by WPT's URL constructor tests.
pub fn expectProperty(
    allocator: std.mem.Allocator,
    url: *const Url,
    property: Property,
    expected: []const u8,
) !void {
    const serialized: ?[]u8 = switch (property) {
        .origin => try url.serializeOrigin(allocator),
        .searchParams => try url.serializeSearchParams(allocator),
        else => null,
    };
    defer if (serialized) |text| allocator.free(text);
    const actual = switch (property) {
        .href => url.source,
        .protocol => url.source[0 .. url.parsed.scheme.end() + 1],
        .username => url.username(),
        .password => url.password() orelse "",
        .host => if (url.parsed.host) |host|
            url.source[host.begin..if (url.parsed.port) |port| port.end() else host.end()]
        else
            "",
        .hostname => if (url.parsed.host) |host| url.sliceC(host) else "",
        .port => if (url.parsed.port) |port| url.sliceC(port) else "",
        .pathname => url.path(),
        .search => componentWithDelimiter(url, url.parsed.query),
        .hash => componentWithDelimiter(url, url.parsed.fragment),
        .origin, .searchParams => serialized.?,
    };
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print(
            "  {s}: expected {s}, got {s}\n",
            .{ @tagName(property), expected, actual },
        );
        return error.UnexpectedUrl;
    }
}

fn componentWithDelimiter(url: *const Url, component: ?Url.Component) []const u8 {
    const range = component orelse return "";
    if (range.len == 0) return "";
    return url.source[range.begin - 1 .. range.end()];
}

/// WPT uses JavaScript strings. URL input replaces lone surrogates with U+FFFD.
fn replaceSurrogates(text: []u8) void {
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] != '\\') {
            i += 1;
            continue;
        }
        const cp = escapedCodeUnit(text[i..]) orelse {
            i += 2;
            continue;
        };
        if (cp >= 0xD800 and cp <= 0xDBFF) {
            if (escapedCodeUnit(text[i + 6 ..])) |low| {
                if (low >= 0xDC00 and low <= 0xDFFF) {
                    i += 12;
                    continue;
                }
            }
        }
        if (cp >= 0xD800 and cp <= 0xDFFF) @memcpy(text[i + 2 ..][0..4], "FFFD");
        i += 6;
    }
}

fn escapedCodeUnit(text: []const u8) ?u16 {
    if (text.len < 6 or text[0] != '\\' or text[1] != 'u') return null;
    return std.fmt.parseInt(u16, text[2..6], 16) catch null;
}

pub fn expectHostCase(allocator: std.mem.Allocator, item: std.json.Value) !void {
    const input = item.object.get("input").?.string;
    const expected = item.object.get("output").?;
    const text = try std.fmt.allocPrint(allocator, "https://{s}/x", .{input});
    defer allocator.free(text);
    const url = parse(allocator, text, .{}) catch |err| {
        if (expected == .null and isUrlFailure(err)) return;
        return err;
    };
    defer url.deinit(allocator);
    if (expected == .null) return error.ExpectedFailure;

    try expectProperty(allocator, &url, .host, expected.string);
    try expectProperty(allocator, &url, .hostname, expected.string);
    try expectProperty(allocator, &url, .pathname, "/x");
    const href = try std.fmt.allocPrint(allocator, "https://{s}/x", .{expected.string});
    defer allocator.free(href);
    try expectProperty(allocator, &url, .href, href);
}
