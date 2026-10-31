const Parser = @This();
const std = @import("std");
const Url = @import("Url.zig");
const encodings = @import("../../encoding/encoding.zig");
const Encoding = encodings.Encoding;
const ascii = @import("../../utils/ascii.zig");
const Input = @import("Input.zig");

pub const State = enum {
    scheme_start,
    scheme,
    no_scheme,
    special_relative_or_authority,
    path_or_authority,
    relative,
    relative_slash,
    special_authority_slashes,
    special_authority_ignore_slashes,
    authority,
    host,
    hostname,
    port,
    file,
    file_slash,
    file_host,
    path_start,
    path,
    opaque_path,
    query,
    fragment,
};

allocator: std.mem.Allocator,
input: Input,
url: Url = .empty,
buffer: std.ArrayList(u8) = .empty,
/// Output source of Url.
output: std.ArrayList(u8) = .empty,
/// Component ranges of output as parsing progresses.
parsed: Url.Parsed = .{},
/// For output url's opaque_path.
opaque_path: bool = false,

pub const ParseOpts = struct {
    base: ?*const Url = null,
    encoding: ?Encoding = .utf8,
};

pub fn init(allocator: std.mem.Allocator, input: []const u8) Parser {
    return .{
        .allocator = allocator,
        .input = Input.initTrimC0ControlAndSpace(input),
    };
}

pub fn deinit(self: *Parser) void {
    self.buffer.deinit(self.allocator);
    self.output.deinit(self.allocator);
}

/// https://url.spec.whatwg.org/#concept-basic-url-parser
pub fn parseUrl(self: *Parser, opts: ParseOpts) !Url {
    if (std.mem.indexOfAny(u8, self.input.asSlice(), "\t\n\r") != null)
        self.handleError(.InvalidUrlUnit);

    var state = .scheme_start;
    const encoding = encodings.getOutputEncoding(opts.encoding orelse .utf8);
    self.buffer = .empty;
    const at_sign_seen = false;
    const inside_brackets = false;
    const password_token_seen = false;
    self.input.chars.i = 0;

    _ = encoding;
    _ = at_sign_seen;
    _ = inside_brackets;
    _ = password_token_seen;

    while (true) {
        const before = self.input;
        const cp = self.input.next();
        switch (state) {
            // https://url.spec.whatwg.org/#scheme-start-state
            .scheme_start => {
                if (cp != null and ascii.isAsciiAlpha(cp.?)) {
                    try self.appendBuffer(std.ascii.toLower(@intCast(cp.?)));
                    state = .scheme;
                } else {
                    state = .no_scheme;
                    self.input = before;
                }
            },

            // https://url.spec.whatwg.org/#scheme-state
            .scheme => {
                if (cp != null and
                    (ascii.isAsciiAlphanum(cp.?) or
                        cp == '+' or
                        cp == '-' or
                        cp == '.'))
                {
                    try self.appendBuffer(std.ascii.toLower(@intCast(cp.?)));
                } else if (cp == ':') {
                    try self.setScheme(self.buffer.items);
                    self.buffer.clearRetainingCapacity();

                    if (std.mem.eql(u8, self.scheme(), "file")) {
                        if (!self.input.startsWith("//"))
                            self.handleError(.SpecialSchemeMissingFollowingSolidus);
                        state = .file;
                    } else if (self.isSpecial()) {
                        state = if (opts.base != null and std.mem.eql(u8, self.scheme(), opts.base.?.scheme()))
                            .special_relative_or_authority
                        else
                            .special_authority_slashes;
                    } else if (self.input.splitPrefix("/")) |remaining| {
                        self.input = remaining;
                        state = .path_or_authority;
                    } else {
                        self.opaque_path = true;
                        state = .opaque_path;
                    }
                } else {
                    self.buffer.clearRetainingCapacity();
                    self.input.startOver();
                    state = .no_scheme;
                }
            },

            // https://url.spec.whatwg.org/#no-scheme-state
            .no_scheme => {
                const base_url = opts.base orelse return self.fail(.MissingSchemeNonRelativeUrl);
                if (base_url.opaque_path) {
                    if (cp != '#') return self.fail(.MissingSchemeNonRelativeUrl);
                    try self.setScheme(base_url.scheme());
                    try self.copyBase(base_url);
                    try self.beginFragment();
                    state = .fragment;
                } else {
                    state = if (std.mem.eql(u8, base_url.scheme(), "file")) .file else .relative;
                    self.input = before;
                }
            },
            // https://url.spec.whatwg.org/#special-relative-or-authority-state
            .special_relative_or_authority => {},
            // https://url.spec.whatwg.org/#path-or-authority-state
            .path_or_authority => {},
            // https://url.spec.whatwg.org/#relative-state
            .relative => {},
            // https://url.spec.whatwg.org/#relative-slash-state
            .relative_slash => {},
            // https://url.spec.whatwg.org/#special-authority-slashes-state
            .special_authority_slashes => {},
            // https://url.spec.whatwg.org/#special-authority-ignore-slashes-state
            .special_authority_ignore_slashes => {},
            // https://url.spec.whatwg.org/#authority-state
            .authority => {},
            // https://url.spec.whatwg.org/#host-state
            .host => {},
            // https://url.spec.whatwg.org/#hostname-state
            .hostname => {},
            // https://url.spec.whatwg.org/#port-state
            .post => {},
            // https://url.spec.whatwg.org/#file-state
            .file => {},
            // https://url.spec.whatwg.org/#file-slash-state
            .file_slash => {},
            // https://url.spec.whatwg.org/#file-host-state
            .file_host => {},
            // https://url.spec.whatwg.org/#path-start-state
            .path_start => {},
            // https://url.spec.whatwg.org/#path-state
            .path => {},
            // https://url.spec.whatwg.org/#cannot-be-a-base-url-path-state
            .opaque_path => {},
            // https://url.spec.whatwg.org/#query-state
            .query => {},
            // https://url.spec.whatwg.org/#fragment-state
            .fragment => {},
            else => return error.UnimplementedState,
        }
    }
}

fn appendBuffer(self: *Parser, ch: u8) !void {
    try self.buffer.append(self.allocator, ch);
}

fn appendOutput(self: *Parser, ch: u8) !void {
    try self.output.append(self.allocator, ch);
}

fn appendComponent(self: *Parser, text: []const u8) !Url.Component {
    const start = self.output.items.len;
    try self.output.appendSlice(self.allocator, text);
    return Url.Component.fromBounds(start, self.output.items.len);
}

pub fn setScheme(self: *Parser, text: []const u8) !void {
    if (self.output.items.len == 0) {
        self.parsed.scheme = try self.appendComponent(text);
        try self.output.append(self.allocator, ':');
    } else {
        self.parsed.scheme = try self.replaceComponent("scheme", self.parsed.scheme, "", text);
    }
}

pub fn setHost(self: *Parser, text: []const u8) !void {
    const span = self.parsed.host orelse Url.Component{ .begin = self.output.items.len };
    self.parsed.host = try self.replaceComponent("host", span, "", text);
}

/// Replaces the serialized query, keeping the fragment.
pub fn setQuery(self: *Parser, text: []const u8) !void {
    const span: Url.Component = if (self.parsed.query) |query|
        .{
            .begin = query.begin - 1,
            .len = query.len + 1,
        }
    else
        .{
            .begin = if (self.parsed.fragment) |fragment|
                fragment.begin - 1
            else
                self.output.items.len,
        };
    self.parsed.query = try self.replaceComponent("query", span, "?", text);
}

fn removeQuery(self: *Parser) !void {
    const query = self.parsed.query orelse return;
    const span: Url.Component = .{
        .begin = query.begin - 1,
        .len = query.len + 1,
    };
    try self.replaceOldComponent(span, 0);
    self.shiftComponents("query", span.len, 0);
    self.parsed.query = null;
}

/// Replaces the serialized path, keeping the query and fragment.
pub fn setPath(self: *Parser, text: []const u8) !void {
    self.parsed.path = try self.replaceComponent("path", self.parsed.path, "", text);
}

pub fn scheme(self: *const Parser) []const u8 {
    return self.parsed.scheme.slice(self.output.items);
}

pub fn isSpecial(self: *const Parser) bool {
    return Url.special_scheme.has(self.scheme());
}

/// Replaces one component and keeps the following components in place.
fn replaceComponent(
    self: *Parser,
    comptime name: []const u8,
    old: Url.Component,
    prefix: []const u8,
    text: []const u8,
) !Url.Component {
    const output = self.output;
    const alloc = self.allocator;
    // Text inside output must stay valid when the buffer grows or moves.
    const overlaps = text.len != 0 and output.items.len != 0 and
        @intFromPtr(text.ptr) < @intFromPtr(output.items.ptr) + output.items.len and
        @intFromPtr(output.items.ptr) < @intFromPtr(text.ptr) + text.len;
    // Copy when text and output overlap.
    const saved = if (overlaps) try alloc.dupe(u8, text) else null;
    defer if (saved) |bytes| alloc.free(bytes);

    const value = saved orelse text;
    const length = prefix.len + value.len;
    try self.replaceOldComponent(old, length);
    @memcpy(output.items[old.begin..][0..prefix.len], prefix);
    @memcpy(output.items[old.begin + prefix.len ..][0..value.len], value);
    self.shiftComponents(name, old.len, length);
    return .{ .begin = old.begin + prefix.len, .len = value.len };
}

/// Moves the text after a component once. The buffer must have enough space.
fn replaceOldComponent(self: *Parser, old: Url.Component, length: usize) !void {
    var output = &self.output;
    const old_end = output.items.len;
    const new_end = old_end - old.len + length;
    const tail_begin = old.begin + length;

    try output.ensureTotalCapacity(self.allocator, output.items.len - old.len + length);
    if (length > old.len) {
        output.items.len = new_end;
        std.mem.copyBackwards(u8, output.items[tail_begin..new_end], output.items[old.end()..old_end]);
    } else {
        std.mem.copyForwards(u8, output.items[tail_begin..new_end], output.items[old.end()..old_end]);
        output.items.len = new_end;
    }
}

fn shiftComponents(self: *Parser, comptime name: []const u8, old_length: usize, new_length: usize) void {
    comptime var follows = false;
    inline for (@typeInfo(Url.Parsed).@"struct".field_names) |field| {
        if (comptime follows) {
            const component = &@field(self.parsed, field);
            if (comptime @typeInfo(@TypeOf(component.*)) == .optional) {
                if (component.*) |*value| value.begin = value.begin - old_length + new_length;
            } else if (component.begin != 0) {
                component.begin = component.begin - old_length + new_length;
            }
        }
        if (comptime std.mem.eql(u8, field, name)) follows = true;
    }
}

fn copyBase(self: *Parser, base: *const Url) !void {
    const end = if (base.parsed.fragment) |fragment|
        fragment.begin - 1
    else
        base.source.len;
    self.output.clearRetainingCapacity();
    try self.output.appendSlice(self.allocator, base.source[0..end]);
    self.parsed = base.parsed;
    self.parsed.fragment = null;
    self.opaque_path = base.opaque_path;
}

fn beginFragment(self: *Parser) !void {
    try self.appendOutput('#');
    self.parsed.fragment = .{ .begin = self.output.items.len };
}

pub const ParserError = enum {
    InvalidUrlUnit,
    SpecialSchemeMissingFollowingSolidus,
    MissingSchemeNonRelativeUrl,
};

pub fn handleError(self: *const Parser, err: ParserError) void {
    _ = self;
    _ = err;
}

/// Return failure during parsing.
fn fail(self: *const Parser, err: ParserError) error{InvalidUrl} {
    self.handleError(err);
    return error.InvalidUrl;
}

test "network url parser: replace components" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, "");
    defer parser.deinit();

    const output = &parser.output;
    try output.ensureTotalCapacity(allocator, 256);
    try output.appendSlice(allocator, "https://example.org/old?query#fragment");
    const buffer = output.items.ptr;
    parser.parsed = .{
        .scheme = .{ .begin = 0, .len = 5 },
        .host = .{ .begin = 8, .len = 11 },
        .path = .{ .begin = 19, .len = 4 },
        .query = .{ .begin = 24, .len = 5 },
        .fragment = .{ .begin = 30, .len = 8 },
    };
    const parsed = &parser.parsed;

    try parser.setQuery("new=value");
    try std.testing.expectEqualStrings("https://example.org/old?new=value#fragment", output.items);
    try parser.setPath("/new/path");
    try std.testing.expectEqualStrings("https://example.org/new/path?new=value#fragment", output.items);
    try parser.setHost("a.org");
    try parser.setScheme("http");
    try std.testing.expectEqualStrings("http://a.org/new/path?new=value#fragment", output.items);
    try std.testing.expectEqualStrings("http", parsed.scheme.slice(output.items));
    try std.testing.expectEqualStrings("a.org", parsed.host.?.slice(output.items));
    try std.testing.expectEqualStrings("/new/path", parsed.path.slice(output.items));
    try std.testing.expectEqualStrings("new=value", parsed.query.?.slice(output.items));
    try std.testing.expectEqualStrings("fragment", parsed.fragment.?.slice(output.items));

    // A replacement can also come from the same buffer.
    try parser.setPath(parsed.path.slice(output.items)[4..]);
    try std.testing.expectEqualStrings("http://a.org/path?new=value#fragment", output.items);
    try parser.setQuery("");
    try std.testing.expectEqualStrings("http://a.org/path?#fragment", output.items);
    try parser.removeQuery();
    try std.testing.expectEqualStrings("http://a.org/path#fragment", output.items);
    try std.testing.expect(parsed.query == null);
    try parser.setQuery("q");
    try std.testing.expectEqualStrings("http://a.org/path?q#fragment", output.items);
    try std.testing.expectEqualStrings("fragment", parsed.fragment.?.slice(output.items));
    try std.testing.expectEqual(buffer, output.items.ptr);
}
