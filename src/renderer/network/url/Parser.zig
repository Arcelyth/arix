const Parser = @This();
const std = @import("std");
const Url = @import("Url.zig");
const encodings = @import("../../encoding/encoding.zig");
const Encoding = encodings.Encoding;
const ascii = @import("../../utils/ascii.zig");
const Input = @import("Input.zig");
const paths = @import("path.zig");
const hosts = @import("host.zig");
const percent = @import("percent_encoded.zig");
const ErrorAdapter = @import("ErrorAdapter.zig");
const ParserError = @import("error.zig").ParserError;

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
adapter: ?ErrorAdapter = null,
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

    var state: State = .scheme_start;
    var encoding = encodings.getOutputEncoding(opts.encoding orelse .utf8);
    self.buffer.clearRetainingCapacity();
    var at_sign_seen = false;
    var inside_brackets = false;
    var password_token_seen = false;
    // The host start position in input's bytes.
    var host_start: usize = 0;
    self.input.startOver();

    parse: while (true) {
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
            .special_relative_or_authority => {
                if (cp == '/' and self.input.startsWith("/")) {
                    _ = self.input.next();
                    state = .special_authority_ignore_slashes;
                } else {
                    self.handleError(.SpecialSchemeMissingFollowingSolidus);
                    state = .relative;
                    self.input = before;
                }
            },

            // https://url.spec.whatwg.org/#path-or-authority-state
            .path_or_authority => {
                if (cp == '/') {
                    try self.beginAuthority();
                    state = .authority;
                } else {
                    state = .path;
                    self.input = before;
                }
            },

            // https://url.spec.whatwg.org/#relative-state
            .relative => {
                const base_url = opts.base.?;
                try self.setScheme(base_url.scheme());
                if (cp == '/' or (self.isSpecial() and cp == '\\')) {
                    if (cp == '\\') self.handleError(.InvalidReverseSolidus);
                    state = .relative_slash;
                    continue :parse;
                }
                try self.copyBase(base_url);
                if (cp == '?') {
                    try self.setQuery("");
                    state = .query;
                } else if (cp == '#') {
                    try self.beginFragment();
                    state = .fragment;
                } else if (cp != null) {
                    try self.removeQuery();
                    paths.shorten(&self.output, &self.parsed, self.opaque_path);
                    state = .path;
                    self.input = before;
                } else break :parse;
            },

            // https://url.spec.whatwg.org/#relative-slash-state
            .relative_slash => {
                if (self.isSpecial() and (cp == '/' or cp == '\\')) {
                    if (cp == '\\') self.handleError(.InvalidReverseSolidus);
                    state = .special_authority_ignore_slashes;
                } else if (cp == '/') {
                    try self.beginAuthority();
                    state = .authority;
                } else {
                    try self.copyAuthority(opts.base.?);
                    state = .path;
                    self.input = before;
                }
            },

            // https://url.spec.whatwg.org/#special-authority-slashes-state
            .special_authority_slashes => {
                if (cp == '/' and self.input.startsWith("/")) {
                    _ = self.input.next();
                    state = .special_authority_ignore_slashes;
                } else {
                    self.handleError(.SpecialSchemeMissingFollowingSolidus);
                    state = .special_authority_ignore_slashes;
                    self.input = before;
                }
            },

            // https://url.spec.whatwg.org/#special-authority-ignore-slashes-state
            .special_authority_ignore_slashes => {
                if (cp == '/' or cp == '\\') {
                    self.handleError(.SpecialSchemeMissingFollowingSolidus);
                } else {
                    try self.beginAuthority();
                    state = .authority;
                    self.input = before;
                }
            },

            // https://url.spec.whatwg.org/#authority-state
            .authority => {
                if (self.buffer.items.len == 0) host_start = before.chars.i;
                if (cp == '@') {
                    self.handleError(.InvalidCredentials);
                    if (at_sign_seen) try self.appendCredential('@', password_token_seen);
                    at_sign_seen = true;
                    var chars = std.unicode.Utf8Iterator{ .bytes = self.buffer.items, .i = 0 };
                    while (chars.nextCodepoint()) |char| {
                        if (char == ':' and !password_token_seen) {
                            password_token_seen = true;
                        } else {
                            try self.appendCredential(char, password_token_seen);
                        }
                    }
                    self.buffer.clearRetainingCapacity();
                } else if (self.isAuthorityEnd(cp)) {
                    if (at_sign_seen and self.buffer.items.len == 0) return self.fail(.HostMissing);
                    self.input.chars.i = host_start;
                    self.buffer.clearRetainingCapacity();
                    try self.finishCredentials();
                    state = .host;
                } else try self.appendRaw(cp.?);
            },

            // https://url.spec.whatwg.org/#host-state
            // https://url.spec.whatwg.org/#hostname-state
            .host, .hostname => {
                if (cp == ':' and !inside_brackets) {
                    if (self.buffer.items.len == 0) return self.fail(.HostMissing);
                    try self.parseHost(self.buffer.items);
                    self.buffer.clearRetainingCapacity();
                    state = .port;
                } else if (self.isAuthorityEnd(cp)) {
                    if (self.isSpecial() and self.buffer.items.len == 0) return self.fail(.HostMissing);
                    try self.parseHost(self.buffer.items);
                    self.buffer.clearRetainingCapacity();
                    state = .path_start;
                    self.input = before;
                } else {
                    if (cp == '[') inside_brackets = true;
                    if (cp == ']') inside_brackets = false;
                    try self.appendRaw(cp.?);
                }
            },

            // https://url.spec.whatwg.org/#port-state
            .port => {
                if (cp != null and ascii.isAsciiDigit(cp.?)) {
                    try self.appendBuffer(@intCast(cp.?));
                } else if (self.isAuthorityEnd(cp)) {
                    if (self.buffer.items.len != 0) {
                        const value = std.fmt.parseInt(u16, self.buffer.items, 10) catch return self.fail(.PortOutOfRange);
                        const default = Url.special_scheme.get(self.scheme()) orelse null;
                        if (default == null or default.? != value)
                            try self.appendPort(value);
                    }
                    self.buffer.clearRetainingCapacity();
                    state = .path_start;
                    self.input = before;
                } else return self.fail(.PortInvalid);
            },

            // https://url.spec.whatwg.org/#file-state
            .file => {
                try self.setScheme("file");
                try self.beginAuthority();
                try self.setHost("");
                const file_base = if (opts.base) |base|
                    if (std.mem.eql(u8, base.scheme(), "file")) base else null
                else
                    null;
                if (cp == '/' or cp == '\\') {
                    if (cp == '\\') self.handleError(.InvalidReverseSolidus);
                    state = .file_slash;
                } else if (file_base) |base| {
                    try self.setHost(base.parsed.host.?.slice(base.source));
                    self.parsed.path = .{
                        .begin = self.output.items.len,
                    };
                    try self.setPath(base.path());
                    if (base.query()) |query| try self.setQuery(query);
                    if (cp == '?') {
                        try self.setQuery("");
                        state = .query;
                    } else if (cp == '#') {
                        try self.beginFragment();
                        state = .fragment;
                    } else if (cp != null) {
                        try self.removeQuery();
                        if (!paths.startsWithWindowsDriveLetter(&before)) {
                            paths.shorten(&self.output, &self.parsed, self.opaque_path);
                        } else {
                            self.handleError(.FileInvalidWindowsDriveLetter);
                            try self.setPath("");
                        }
                        state = .path;
                        self.input = before;
                    } else break :parse;
                } else {
                    state = .path;
                    self.input = before;
                }
            },

            // https://url.spec.whatwg.org/#file-slash-state
            .file_slash => {
                if (cp == '/' or cp == '\\') {
                    if (cp == '\\') self.handleError(.InvalidReverseSolidus);
                    state = .file_host;
                } else {
                    if (opts.base) |base| {
                        if (std.mem.eql(u8, base.scheme(), "file")) {
                            try self.setHost(base.parsed.host.?.slice(base.source));
                            self.parsed.path = .{ .begin = self.output.items.len };
                            const path = base.path();
                            const first_start = @min(1, path.len);
                            const first_end = std.mem.indexOfScalarPos(u8, path, first_start, '/') orelse path.len;
                            const first = path[first_start..first_end];
                            if (!paths.startsWithWindowsDriveLetter(&before) and paths.isNormalizedWindowsDriveLetter(first)) {
                                try self.appendOutput('/');
                                try self.output.appendSlice(self.allocator, first);
                                self.parsed.path.len = self.output.items.len - self.parsed.path.begin;
                            }
                        }
                    }
                    state = .path;
                    self.input = before;
                }
            },

            // https://url.spec.whatwg.org/#file-host-state
            .file_host => {
                if (cp == null or cp == '/' or cp == '\\' or cp == '?' or cp == '#') {
                    self.input = before;
                    if (paths.isWindowsDriveLetter(self.buffer.items)) {
                        self.handleError(.FileInvalidWindowsDriveLetterHost);
                        state = .path;
                    } else if (self.buffer.items.len == 0) {
                        try self.setHost("");
                        state = .path_start;
                    } else {
                        try self.parseHost(self.buffer.items);
                        if (std.mem.eql(u8, self.parsed.host.?.slice(self.output.items), "localhost"))
                            try self.setHost("");
                        self.buffer.clearRetainingCapacity();
                        state = .path_start;
                    }
                } else try self.appendRaw(cp.?);
            },

            // https://url.spec.whatwg.org/#path-start-state
            .path_start => {
                self.parsed.path = .{
                    .begin = self.output.items.len,
                };
                if (self.isSpecial()) {
                    if (cp == '\\') self.handleError(.InvalidReverseSolidus);
                    state = .path;
                    if (cp != '/' and cp != '\\') self.input = before;
                } else if (cp == '?') {
                    try self.setQuery("");
                    state = .query;
                } else if (cp == '#') {
                    try self.beginFragment();
                    state = .fragment;
                } else if (cp != null) {
                    state = .path;
                    if (cp != '/') self.input = before;
                } else break :parse;
            },

            // https://url.spec.whatwg.org/#path-state
            .path => {
                if (self.parsed.path.begin == 0)
                    self.parsed.path.begin = self.output.items.len;
                const separator = cp == '/' or (self.isSpecial() and cp == '\\');
                if (cp == null or separator or cp == '?' or cp == '#') {
                    if (cp == '\\' and self.isSpecial()) self.handleError(.InvalidReverseSolidus);
                    try self.appendPathSegment(separator);
                    self.buffer.clearRetainingCapacity();
                    if (cp == '?') {
                        try self.setQuery("");
                        state = .query;
                    }
                    if (cp == '#') {
                        try self.beginFragment();
                        state = .fragment;
                    }
                    if (cp == null) break :parse;
                } else {
                    self.validateUnit(cp.?);
                    try percent.append(self.allocator, &self.buffer, cp.?, .path);
                }
            },

            // https://url.spec.whatwg.org/#cannot-be-a-base-url-path-state
            .opaque_path => {
                if (self.parsed.path.begin == 0)
                    self.parsed.path.begin = self.output.items.len;
                if (cp == '?') {
                    try self.setQuery("");
                    state = .query;
                } else if (cp == '#') {
                    try self.beginFragment();
                    state = .fragment;
                } else if (cp == ' ') {
                    self.handleError(.InvalidUrlUnit);
                    if (self.input.startsWith("?") or self.input.startsWith("#"))
                        try self.output.appendSlice(self.allocator, "%20")
                    else
                        try self.appendOutput(' ');
                    self.parsed.path.len = self.output.items.len - self.parsed.path.begin;
                } else if (cp) |char| {
                    self.validateUnit(char);
                    try percent.append(self.allocator, &self.output, char, .c0_control);
                    self.parsed.path.len = self.output.items.len - self.parsed.path.begin;
                } else break :parse;
            },

            // https://url.spec.whatwg.org/#query-state
            .query => {
                if (encoding != .utf8 and (!self.isSpecial() or
                    std.mem.eql(u8, self.scheme(), "ws") or std.mem.eql(u8, self.scheme(), "wss")))
                    encoding = .utf8;
                if (cp == null or cp == '#') {
                    try percent.percentEncodeAfterEncoding(
                        self.allocator,
                        &self.output,
                        self.buffer.items,
                        encoding,
                        if (self.isSpecial()) .special_query else .query,
                    );
                    self.parsed.query.?.len = self.output.items.len - self.parsed.query.?.begin;
                    self.buffer.clearRetainingCapacity();
                    if (cp == '#') {
                        try self.beginFragment();
                        state = .fragment;
                    } else break :parse;
                } else {
                    self.validateUnit(cp.?);
                    try self.appendRaw(cp.?);
                }
            },

            // https://url.spec.whatwg.org/#fragment-state
            .fragment => {
                if (cp) |char| {
                    self.validateUnit(char);
                    try percent.append(self.allocator, &self.output, char, .fragment);
                } else break :parse;
            },
        }
    }
    if (self.parsed.fragment) |*fragment|
        fragment.len = self.output.items.len - fragment.begin;
    try self.normalizePathPrefix();
    self.url = .{
        .source = try self.output.toOwnedSlice(self.allocator),
        .parsed = self.parsed,
        .opaque_path = self.opaque_path,
    };
    return self.url;
}

pub fn appendBuffer(self: *Parser, ch: u8) !void {
    try self.buffer.append(self.allocator, ch);
}

pub fn appendOutput(self: *Parser, ch: u8) !void {
    try self.output.append(self.allocator, ch);
}

pub fn appendComponent(self: *Parser, text: []const u8) !Url.Component {
    const start = self.output.items.len;
    try self.output.appendSlice(self.allocator, text);
    return Url.Component.fromBounds(start, self.output.items.len);
}

/// Converts a Unicode code point to UTF-8 bytes and appends them to the buffer
/// without percent-encoding.
pub fn appendRaw(self: *Parser, cp: u21) !void {
    var bytes: [4]u8 = undefined;
    const length = try std.unicode.utf8Encode(cp, &bytes);
    try self.buffer.appendSlice(self.allocator, bytes[0..length]);
}

/// Appends a code point to the username or password component.
/// Inserts the `:` separator between the username and password.
/// The code point is percent-encoded using the userinfo percent-encode set.
pub fn appendCredential(self: *Parser, cp: u21, password: bool) !void {
    if (password and self.parsed.password == null) {
        try self.appendOutput(':');
        self.parsed.password = .{
            .begin = self.output.items.len,
        };
    }
    try percent.append(self.allocator, &self.output, cp, .userinfo);
    const component = if (password)
        &self.parsed.password.?
    else
        &self.parsed.username.?;
    component.len = self.output.items.len - component.begin;
}

pub fn appendPort(self: *Parser, value: u16) !void {
    try self.appendOutput(':');
    var bytes: [5]u8 = undefined;
    self.parsed.port = try self.appendComponent(try std.fmt.bufPrint(&bytes, "{d}", .{value}));
}

/// Resolves dot segments and appends one completed path segment.
fn appendPathSegment(self: *Parser, separator: bool) !void {
    const segment = self.buffer.items;
    if (paths.isDoubleDot(segment)) {
        paths.shorten(&self.output, &self.parsed, self.opaque_path);
        if (!separator) try self.appendOutput('/');
    } else if (paths.isSingleDot(segment)) {
        if (!separator) try self.appendOutput('/');
    } else {
        if (std.mem.eql(u8, self.scheme(), "file") and self.parsed.path.len == 0 and paths.isWindowsDriveLetter(segment))
            segment[1] = ':';
        try self.appendOutput('/');
        try self.output.appendSlice(self.allocator, segment);
    }
    self.parsed.path.len = self.output.items.len - self.parsed.path.begin;
}

pub fn finishCredentials(self: *Parser) !void {
    if (self.parsed.username.?.len != 0 or self.parsed.password != null)
        try self.appendOutput('@');
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
    const output = &self.output;
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

/// Sets output and ranges to the base URL without its fragment
/// and whether the path is opaque.
pub fn copyBase(self: *Parser, base: *const Url) !void {
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

/// Sets output to the base scheme, credentials, host, and port.
/// Updates those ranges before parsing a new path.
pub fn copyAuthority(self: *Parser, base: *const Url) !void {
    const end = if (base.parsed.port) |port| port.end() else if (base.parsed.host) |host| host.end() else base.parsed.scheme.end() + 1;
    self.output.clearRetainingCapacity();
    try self.output.appendSlice(self.allocator, base.source[0..end]);
    self.parsed.scheme = base.parsed.scheme;
    self.parsed.username = base.parsed.username;
    self.parsed.password = base.parsed.password;
    self.parsed.host = base.parsed.host;
    self.parsed.port = base.parsed.port;
}

fn beginFragment(self: *Parser) !void {
    try self.appendOutput('#');
    self.parsed.fragment = .{ .begin = self.output.items.len };
}

fn beginAuthority(self: *Parser) !void {
    self.output.shrinkRetainingCapacity(self.parsed.scheme.end() + 1);
    try self.output.appendSlice(self.allocator, "//");
    self.parsed.username = .{ .begin = self.output.items.len };
    self.parsed.password = null;
    self.parsed.host = null;
    self.parsed.port = null;
    self.parsed.query = null;
    self.parsed.fragment = null;
}

inline fn isAuthorityEnd(self: *Parser, cp: ?u21) bool {
    return cp == null or cp == '/' or cp == '?' or cp == '#' or (self.isSpecial() and cp == '\\');
}

pub fn parseHost(self: *Parser, text: []const u8) !void {
    const host = try hosts.parse(self.allocator, text, !self.isSpecial(), self.adapter);
    defer self.allocator.free(host);
    try self.setHost(host);
}

/// Reports invalid URL code points and malformed percent escapes.
pub fn validateUnit(self: *const Parser, cp: u21) void {
    if (cp == '%') {
        var remaining = self.input;
        const first = remaining.next();
        const second = remaining.next();
        if (first == null or second == null or
            !ascii.isAsciiHexDigit(first.?) or !ascii.isAsciiHexDigit(second.?))
            self.handleError(.InvalidUrlUnit);
    } else if (!hosts.isUrlCodePoint(cp)) self.handleError(.InvalidUrlUnit);
}

/// Adds or removes the `/.` prefix used when a path could look like an authority.
fn normalizePathPrefix(self: *Parser) !void {
    if (self.opaque_path or self.parsed.host != null) return;
    const start = self.parsed.scheme.end() + 1;
    const needed = std.mem.startsWith(u8, self.parsed.path.slice(self.output.items), "//");
    const present = self.parsed.path.begin == start + 2;
    if (needed == present) return;
    const old_length: usize = if (present) 2 else 0;
    const new_length: usize = if (needed) 2 else 0;
    try self.replaceOldComponent(
        .{ .begin = start, .len = old_length },
        new_length,
    );
    if (needed) @memcpy(self.output.items[start..][0..2], "/.");
    self.parsed.path.begin = self.parsed.path.begin - old_length + new_length;
    self.shiftComponents("path", old_length, new_length);
}

pub fn handleError(self: *const Parser, err: ParserError) void {
    if (self.adapter) |adapter| adapter.handleError(err);
}

/// Reports a fatal validation error and returns its matching Zig error.
pub fn fail(self: *const Parser, comptime err: ParserError) anyerror {
    return ErrorAdapter.fail(self.adapter, err);
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
