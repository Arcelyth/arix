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
url: Url = .empty,
buffer: std.ArrayList(u8) = .empty,
/// Output source of Url.
output: std.ArrayList(u8) = .empty,
// Query and fragment bytes saved while a preceding component is appended.
suffix: std.ArrayList(u8) = .empty,
suffix_query: ?Url.Component = null,
suffix_fragment: ?Url.Component = null,
/// Component ranges of output as parsing progresses.
parsed: Url.Parsed = .{},
/// For output url's opaque_path.
opaque_path: bool = false,

pub const ParseOpts = struct {
    base: ?*const Url = null,
    encoding: ?Encoding = .utf8,
    state_override: ?State = null,
};

pub fn init(allocator: std.mem.Allocator) Parser {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Parser) void {
    self.buffer.deinit(self.allocator);
    self.suffix.deinit(self.allocator);
    self.output.deinit(self.allocator);
}

/// Parses a new URL. Free the result with Url.deinit.
pub fn parse(self: *Parser, text: []const u8, opts: ParseOpts) !Url {
    self.output.clearRetainingCapacity();
    self.parsed = .{};
    self.opaque_path = false;
    try self.parseUrl(text, opts, true);
    return self.finish();
}

/// Parses into an existing URL.
/// Without an override, parsing starts at scheme_start. Overrides use the chosen state's preconditions.
pub fn parseExisting(
    self: *Parser,
    text: []const u8,
    opts: ParseOpts,
    url: *Url,
) !void {
    const saved = if (overlaps(text, url.source))
        try self.allocator.dupe(u8, text)
    else
        null;
    defer if (saved) |bytes| self.allocator.free(bytes);

    var options = opts;
    var base: ?Url = null;
    defer if (base) |value| value.deinit(self.allocator);
    if (opts.base) |value| {
        if (overlaps(value.source, url.source)) {
            base = .{
                .source = try self.allocator.dupe(u8, value.source),
                .parsed = value.parsed,
                .opaque_path = value.opaque_path,
            };
            options.base = &base.?;
        }
    }

    self.output.deinit(self.allocator);
    self.output = std.ArrayList(u8).fromOwnedSlice(url.source);
    self.parsed = url.parsed;
    self.opaque_path = url.opaque_path;
    url.* = .empty;
    const result = self.parseUrl(saved orelse text, options, false);
    const restored = self.restoreSuffix();
    url.* = try self.finish();
    try restored;
    try result;
}

// Transfers an exact-sized output allocation to the URL.
fn finish(self: *Parser) !Url {
    self.url = .{
        .source = try self.output.toOwnedSlice(self.allocator),
        .parsed = self.parsed,
        .opaque_path = self.opaque_path,
    };
    return self.url;
}

/// https://url.spec.whatwg.org/#concept-basic-url-parser
/// If `new` is true, means parsing a new url; otherwise, modifies the existing url.
pub fn parseUrl(
    self: *Parser,
    text: []const u8,
    opts: ParseOpts,
    comptime new: bool,
) !void {
    var input = if (new)
        Input.initTrimC0ControlAndSpace(text)
    else
        Input.initNoTrim(text);

    // Detect whether new URL’s input has leading or trailing C0 controls or spaces.
    if (new and text.len != input.chars.bytes.len) self.handleError(.InvalidUrlUnit);
    if (std.mem.indexOfAny(u8, input.asSlice(), "\t\n\r") != null)
        self.handleError(.InvalidUrlUnit);

    var state: State = if (new)
        .scheme_start
    else
        opts.state_override orelse .scheme_start;

    var encoding = encodings.getOutputEncoding(opts.encoding orelse .utf8);
    self.buffer.clearRetainingCapacity();
    var at_sign_seen = false;
    var inside_brackets = false;
    var password_token_seen = false;
    // The host start position in input's bytes.
    var host_start: usize = 0;

    if (!new) {
        self.suffix.clearRetainingCapacity();
        self.suffix_query = null;
        self.suffix_fragment = null;
    }
    const has_override = if (new) false else opts.state_override != null;

    parse: while (true) {
        const before = input;
        const cp = input.next();
        switch (state) {
            // https://url.spec.whatwg.org/#scheme-start-state
            .scheme_start => {
                if (cp != null and ascii.isAsciiAlpha(cp.?)) {
                    try self.appendBuffer(std.ascii.toLower(@intCast(cp.?)));
                    state = .scheme;
                } else if (has_override) {
                    return error.InvalidScheme;
                } else {
                    state = .no_scheme;
                    input = before;
                }
            },

            // https://url.spec.whatwg.org/#scheme-state
            //
            .scheme => {
                if (cp != null and
                    (ascii.isAsciiAlphanum(cp.?) or
                        cp == '+' or
                        cp == '-' or
                        cp == '.'))
                {
                    try self.appendBuffer(std.ascii.toLower(@intCast(cp.?)));
                } else if (cp == ':') {
                    if (has_override) {
                        if (self.isSpecial() != Url.special_scheme.has(self.buffer.items)) break :parse;
                        if (std.mem.eql(u8, self.buffer.items, "file") and
                            (self.hasCredentials() or self.parsed.port != null)) break :parse;
                        if (std.mem.eql(u8, self.scheme(), "file") and self.parsed.host != null and self.parsed.host.?.len == 0) break :parse;
                    }

                    try self.setScheme(self.buffer.items);
                    if (has_override) {
                        if (self.parsed.port) |port| {
                            const number = std.fmt.parseInt(u16, port.slice(self.output.items), 10) catch unreachable;
                            if (Url.special_scheme.get(self.scheme())) |default| {
                                if (default == number) try self.setPort(null);
                            }
                        }
                        break :parse;
                    }
                    self.buffer.clearRetainingCapacity();

                    if (std.mem.eql(u8, self.scheme(), "file")) {
                        if (!input.startsWith("//"))
                            self.handleError(.SpecialSchemeMissingFollowingSolidus);
                        state = .file;
                    } else if (self.isSpecial()) {
                        state = if (opts.base != null and std.mem.eql(u8, self.scheme(), opts.base.?.scheme()))
                            .special_relative_or_authority
                        else
                            .special_authority_slashes;
                    } else if (input.splitPrefix("/")) |remaining| {
                        input = remaining;
                        state = .path_or_authority;
                    } else {
                        self.opaque_path = true;
                        try self.setPath("");
                        state = .opaque_path;
                    }
                } else if (has_override) {
                    return error.InvalidScheme;
                } else {
                    self.buffer.clearRetainingCapacity();
                    input.startOver();
                    state = .no_scheme;
                }
            },

            // https://url.spec.whatwg.org/#no-scheme-state
            .no_scheme => {
                const base_url = opts.base orelse return self.fail(.MissingSchemeNonRelativeUrl);
                if (base_url.opaque_path) {
                    if (cp != '#') return self.fail(.MissingSchemeNonRelativeUrl);
                    try self.setScheme(base_url.scheme());
                    try self.setPath(base_url.path());
                    self.opaque_path = true;
                    if (base_url.query()) |query| try self.setQuery(query) else try self.removeQuery();
                    try self.beginFragment();
                    state = .fragment;
                } else {
                    state = if (std.mem.eql(u8, base_url.scheme(), "file")) .file else .relative;
                    input = before;
                }
            },

            // https://url.spec.whatwg.org/#special-relative-or-authority-state
            .special_relative_or_authority => {
                if (cp == '/' and input.startsWith("/")) {
                    _ = input.next();
                    state = .special_authority_ignore_slashes;
                } else {
                    self.handleError(.SpecialSchemeMissingFollowingSolidus);
                    state = .relative;
                    input = before;
                }
            },

            // https://url.spec.whatwg.org/#path-or-authority-state
            .path_or_authority => {
                if (cp == '/') {
                    try self.beginAuthority();
                    state = .authority;
                } else {
                    state = .path;
                    input = before;
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
                    input = before;
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
                    input = before;
                }
            },

            // https://url.spec.whatwg.org/#special-authority-slashes-state
            .special_authority_slashes => {
                if (cp == '/' and input.startsWith("/")) {
                    _ = input.next();
                    state = .special_authority_ignore_slashes;
                } else {
                    self.handleError(.SpecialSchemeMissingFollowingSolidus);
                    state = .special_authority_ignore_slashes;
                    input = before;
                }
            },

            // https://url.spec.whatwg.org/#special-authority-ignore-slashes-state
            .special_authority_ignore_slashes => {
                if (cp == '/' or cp == '\\') {
                    self.handleError(.SpecialSchemeMissingFollowingSolidus);
                } else {
                    try self.beginAuthority();
                    state = .authority;
                    input = before;
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
                    // Preserves partial modifications to the existing URL even if parsing fails.
                    if (!new) try self.finishCredentials();
                } else if (self.isAuthorityEnd(cp)) {
                    if (at_sign_seen and self.buffer.items.len == 0) return self.fail(.HostMissing);
                    input.chars.i = host_start;
                    self.buffer.clearRetainingCapacity();
                    try self.finishCredentials();
                    state = .host;
                } else try self.appendRaw(cp.?);
            },

            // https://url.spec.whatwg.org/#host-state
            // https://url.spec.whatwg.org/#hostname-state
            .host, .hostname => {
                if (has_override and std.mem.eql(u8, self.scheme(), "file")) {
                    state = .file_host;
                    input = before;
                } else if (cp == ':' and !inside_brackets) {
                    if (self.buffer.items.len == 0) return self.fail(.HostMissing);
                    if (has_override and opts.state_override == .hostname) return error.HostnameContainsPort;
                    try self.parseHost(self.buffer.items);
                    self.buffer.clearRetainingCapacity();
                    state = .port;
                } else if (self.isAuthorityEnd(cp)) {
                    if (self.isSpecial() and self.buffer.items.len == 0) return self.fail(.HostMissing);
                    if (has_override and self.buffer.items.len == 0 and
                        (self.hasCredentials() or self.parsed.port != null)) return error.HostMissing;
                    try self.parseHost(self.buffer.items);
                    self.buffer.clearRetainingCapacity();
                    if (has_override) break :parse;
                    state = .path_start;
                    input = before;
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
                } else if (self.isAuthorityEnd(cp) or has_override) {
                    if (self.buffer.items.len != 0) {
                        const value = std.fmt.parseInt(u16, self.buffer.items, 10) catch return self.fail(.PortOutOfRange);
                        const default = Url.special_scheme.get(self.scheme()) orelse null;
                        try self.setPort(if (default == value) null else value);
                        self.buffer.clearRetainingCapacity();
                        if (has_override) break :parse;
                    } else if (has_override) return error.PortInvalid;
                    self.buffer.clearRetainingCapacity();
                    state = .path_start;
                    input = before;
                } else return self.fail(.PortInvalid);
            },

            // https://url.spec.whatwg.org/#file-state
            .file => {
                try self.setScheme("file");
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
                    try self.setPath(base.path());
                    if (base.query()) |query| try self.setQuery(query) else try self.removeQuery();
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
                        input = before;
                    } else break :parse;
                } else {
                    state = .path;
                    input = before;
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
                            if (self.parsed.path.begin == 0) self.parsed.path.begin = self.output.items.len;
                            const path = base.path();
                            const first_start = @min(1, path.len);
                            const first_end = std.mem.indexOfScalarPos(u8, path, first_start, '/') orelse path.len;
                            const first = path[first_start..first_end];
                            if (!paths.startsWithWindowsDriveLetter(&before) and paths.isNormalizedWindowsDriveLetter(first)) {
                                if (!new) try self.saveSuffix(.path);
                                try self.appendOutput('/');
                                try self.output.appendSlice(self.allocator, first);
                                self.parsed.path.len = self.output.items.len - self.parsed.path.begin;
                            }
                        }
                    }
                    state = .path;
                    input = before;
                }
            },

            // https://url.spec.whatwg.org/#file-host-state
            .file_host => {
                if (cp == null or cp == '/' or cp == '\\' or cp == '?' or cp == '#') {
                    input = before;
                    if (!has_override and paths.isWindowsDriveLetter(self.buffer.items)) {
                        self.handleError(.FileInvalidWindowsDriveLetterHost);
                        state = .path;
                    } else if (self.buffer.items.len == 0) {
                        try self.setHost("");
                        if (has_override) break :parse;
                        state = .path_start;
                    } else {
                        try self.parseHost(self.buffer.items);
                        if (std.mem.eql(u8, self.parsed.host.?.slice(self.output.items), "localhost"))
                            try self.setHost("");
                        if (has_override) break :parse;
                        self.buffer.clearRetainingCapacity();
                        state = .path_start;
                    }
                } else try self.appendRaw(cp.?);
            },

            // https://url.spec.whatwg.org/#path-start-state
            .path_start => {
                if (self.parsed.path.begin == 0) self.parsed.path.begin = self.output.items.len;
                if (!new) try self.saveSuffix(.path);
                if (self.isSpecial()) {
                    if (cp == '\\') self.handleError(.InvalidReverseSolidus);
                    state = .path;
                    if (cp != '/' and cp != '\\') input = before;
                } else if (!has_override and cp == '?') {
                    try self.setQuery("");
                    state = .query;
                } else if (!has_override and cp == '#') {
                    try self.beginFragment();
                    state = .fragment;
                } else if (cp != null) {
                    state = .path;
                    if (cp != '/') input = before;
                } else {
                    if (has_override and self.parsed.host == null) {
                        try self.appendOutput('/');
                        self.parsed.path.len += 1;
                    }
                    break :parse;
                }
            },

            // https://url.spec.whatwg.org/#path-state
            .path => {
                if (self.parsed.path.begin == 0)
                    self.parsed.path.begin = self.output.items.len;
                if (!new) try self.saveSuffix(.path);
                const separator = cp == '/' or (self.isSpecial() and cp == '\\');
                if (cp == null or separator or (!has_override and (cp == '?' or cp == '#'))) {
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
                    self.validateUnit(cp.?, &input);
                    try percent.append(self.allocator, &self.buffer, cp.?, .path);
                }
            },

            // https://url.spec.whatwg.org/#cannot-be-a-base-url-path-state
            .opaque_path => {
                if (self.parsed.path.begin == 0)
                    self.parsed.path.begin = self.output.items.len;
                if (!new) try self.saveSuffix(.path);
                if (cp == '?') {
                    try self.setQuery("");
                    state = .query;
                } else if (cp == '#') {
                    try self.beginFragment();
                    state = .fragment;
                } else if (cp == ' ') {
                    self.handleError(.InvalidUrlUnit);
                    if (input.startsWith("?") or input.startsWith("#"))
                        try self.output.appendSlice(self.allocator, "%20")
                    else
                        try self.appendOutput(' ');
                    self.parsed.path.len = self.output.items.len - self.parsed.path.begin;
                } else if (cp) |char| {
                    self.validateUnit(char, &input);
                    try percent.append(self.allocator, &self.output, char, .c0_control);
                    self.parsed.path.len = self.output.items.len - self.parsed.path.begin;
                } else break :parse;
            },

            // https://url.spec.whatwg.org/#query-state
            .query => {
                std.debug.assert(self.parsed.query != null);
                if (!new) try self.saveSuffix(.query);
                if (encoding != .utf8 and (!self.isSpecial() or
                    std.mem.eql(u8, self.scheme(), "ws") or std.mem.eql(u8, self.scheme(), "wss")))
                    encoding = .utf8;
                if (cp == null or (!has_override and cp == '#')) {
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
                    self.validateUnit(cp.?, &input);
                    try self.appendRaw(cp.?);
                }
            },

            // https://url.spec.whatwg.org/#fragment-state
            .fragment => {
                std.debug.assert(self.parsed.fragment != null);
                if (cp) |char| {
                    self.validateUnit(char, &input);
                    try percent.append(self.allocator, &self.output, char, .fragment);
                } else break :parse;
            },
        }
    }
    if (self.parsed.fragment) |*fragment|
        fragment.len = self.output.items.len - fragment.begin;
    try self.normalizePathPrefix();
}

// Inserts bytes at a component's end and shifts only the following ranges.
fn appendToComponent(self: *Parser, comptime name: []const u8, text: []const u8) !void {
    const field = &@field(self.parsed, name);
    const component = if (comptime @typeInfo(@TypeOf(field.*)) == .optional) &field.*.? else field;
    _ = try self.replaceComponent(name, .{ .begin = component.end() }, "", text);
    component.len += text.len;
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
        const end = self.parsed.username.?.end();
        _ = try self.replaceComponent("username", .{ .begin = end }, "", ":");
        self.parsed.password = .{ .begin = end + 1 };
    }
    // A UTF-8 code point has at most four bytes, each encoded as %HH.
    var bytes: [12]u8 = undefined;
    const encoded = try percent.encodeCodepoint(cp, .userinfo, &bytes);
    if (password)
        try self.appendToComponent("password", encoded)
    else
        try self.appendToComponent("username", encoded);
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
    if (!self.hasCredentials()) return;
    const end = if (self.parsed.password) |password| password.end() else self.parsed.username.?.end();
    if (end < self.output.items.len and self.output.items[end] == '@') return;
    _ = try self.replaceComponent("password", .{ .begin = end }, "", "@");
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
    const span = self.parsed.host orelse span: {
        try self.beginAuthority();
        try self.finishCredentials();
        const end = if (self.parsed.password) |password| password.end() else self.parsed.username.?.end();
        break :span Url.Component{ .begin = end + @as(usize, @intFromBool(self.hasCredentials())) };
    };
    self.parsed.host = try self.replaceComponent("host", span, "", text);
}

/// Replaces the serialized query, keeping the fragment.
pub fn setQuery(self: *Parser, text: []const u8) !void {
    self.suffix_query = null;
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

/// Removes the query and its '?' separator.
pub fn removeQuery(self: *Parser) !void {
    self.suffix_query = null;
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
    if (self.parsed.path.begin == 0) self.parsed.path.begin = self.output.items.len;
    self.parsed.path = try self.replaceComponent("path", self.parsed.path, "", text);
}

/// Replaces the serialized fragment.
pub fn setFragment(self: *Parser, text: []const u8) !void {
    self.suffix_fragment = null;
    const span: Url.Component = if (self.parsed.fragment) |fragment|
        .{
            .begin = fragment.begin - 1,
            .len = fragment.len + 1,
        }
    else
        .{
            .begin = self.output.items.len,
        };
    self.parsed.fragment = try self.replaceComponent("fragment", span, "#", text);
}

/// Removes the fragment and its '#' separator.
pub fn removeFragment(self: *Parser) !void {
    self.suffix_fragment = null;
    const fragment = self.parsed.fragment orelse return;
    _ = try self.replaceComponent(
        "fragment",
        .{
            .begin = fragment.begin - 1,
            .len = fragment.len + 1,
        },
        "",
        "",
    );
    self.parsed.fragment = null;
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
    // Copy when text and output overlap.
    const saved = if (overlaps(text, output.items)) try alloc.dupe(u8, text) else null;
    defer if (saved) |bytes| alloc.free(bytes);

    const value = saved orelse text;
    const length = prefix.len + value.len;
    try self.replaceOldComponent(old, length);
    @memcpy(output.items[old.begin..][0..prefix.len], prefix);
    @memcpy(output.items[old.begin + prefix.len ..][0..value.len], value);
    self.shiftComponents(name, old.len, length);
    return .{
        .begin = old.begin + prefix.len,
        .len = value.len,
    };
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

/// Sets the scheme, authority, path, and query from the base URL.
/// Keeps the current fragment.
pub fn copyBase(self: *Parser, base: *const Url) !void {
    try self.copyAuthority(base);
    try self.setPath(base.path());
    if (base.query()) |query| try self.setQuery(query) else try self.removeQuery();
    self.opaque_path = base.opaque_path;
}

/// Sets output to the base scheme, credentials, host, and port.
/// Keeps the current path, query, and fragment.
pub fn copyAuthority(self: *Parser, base: *const Url) !void {
    const end = if (base.parsed.port) |port| port.end() else if (base.parsed.host) |host| host.end() else base.parsed.scheme.end() + 1;
    var old_end = if (self.parsed.port) |port| port.end() else if (self.parsed.host) |host| host.end() else @min(self.output.items.len, self.parsed.scheme.end() + 1);
    if (self.parsed.host == null and self.parsed.path.begin == old_end + 2) old_end += 2;
    try self.replaceOldComponent(.{ .len = old_end }, end);
    @memcpy(self.output.items[0..end], base.source[0..end]);
    self.shiftComponents("port", old_end, end);
    if (self.parsed.path.begin == 0) self.parsed.path.begin = end;
    self.parsed.scheme = base.parsed.scheme;
    self.parsed.username = base.parsed.username;
    self.parsed.password = base.parsed.password;
    self.parsed.host = base.parsed.host;
    self.parsed.port = base.parsed.port;
}

fn beginFragment(self: *Parser) !void {
    try self.setFragment("");
}

fn beginAuthority(self: *Parser) !void {
    if (self.parsed.username != null) return;
    const start = self.parsed.scheme.end() + 1;
    if (self.parsed.host == null) {
        const prefix: usize = if (self.parsed.path.begin == start + 2) 2 else 0;
        try self.replaceOldComponent(.{ .begin = start, .len = prefix }, 2);
        @memcpy(self.output.items[start..][0..2], "//");
        self.shiftComponents("scheme", prefix, 2);
    }
    self.parsed.username = .{ .begin = start + 2 };
}

/// Replaces or removes the port, keeping later components.
pub fn setPort(self: *Parser, value: ?u16) !void {
    const span: Url.Component = if (self.parsed.port) |port|
        .{
            .begin = port.begin - 1,
            .len = port.len + 1,
        }
    else
        .{
            .begin = self.parsed.host.?.end(),
        };
    if (value) |number| {
        var bytes: [5]u8 = undefined;
        self.parsed.port = try self.replaceComponent(
            "port",
            span,
            ":",
            try std.fmt.bufPrint(&bytes, "{d}", .{number}),
        );
    } else {
        _ = try self.replaceComponent("port", span, "", "");
        self.parsed.port = null;
    }
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
pub fn validateUnit(self: *const Parser, cp: u21, input: *const Input) void {
    if (cp == '%') {
        var remaining = input.*;
        const first = remaining.next();
        const second = remaining.next();
        if (first == null or second == null or
            !ascii.isAsciiHexDigit(first.?) or !ascii.isAsciiHexDigit(second.?))
            self.handleError(.InvalidUrlUnit);
    } else if (!hosts.isUrlCodePoint(cp)) self.handleError(.InvalidUrlUnit);
}

/// Adds or removes the `/.` prefix used when a path could look like an authority.
fn normalizePathPrefix(self: *Parser) !void {
    if (self.parsed.host != null) return;
    const start = self.parsed.scheme.end() + 1;
    const needed = !self.opaque_path and std.mem.startsWith(u8, self.parsed.path.slice(self.output.items), "//");
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

fn overlaps(a: []const u8, b: []const u8) bool {
    return a.len != 0 and
        b.len != 0 and
        @intFromPtr(a.ptr) < @intFromPtr(b.ptr) + b.len and
        @intFromPtr(b.ptr) < @intFromPtr(a.ptr) + a.len;
}

fn hasCredentials(self: *const Parser) bool {
    return (if (self.parsed.username) |value| value.len != 0 else false) or
        (if (self.parsed.password) |value| value.len != 0 else false);
}

// Saves later components once, so path and query loops only append to output.
fn saveSuffix(self: *Parser, comptime after: enum { path, query }) !void {
    const end = if (after == .path) self.parsed.path.end() else self.parsed.query.?.end();
    if (end == self.output.items.len) return;
    const start = self.suffix.items.len;
    try self.suffix.appendSlice(self.allocator, self.output.items[end..]);
    if (after == .path) {
        if (self.parsed.query) |query| {
            self.suffix_query = .{
                .begin = query.begin - end + start,
                .len = query.len,
            };
            self.parsed.query = null;
        }
    }
    if (self.parsed.fragment) |fragment| {
        self.suffix_fragment = .{
            .begin = fragment.begin - end + start,
            .len = fragment.len,
        };
        self.parsed.fragment = null;
    }
    self.output.shrinkRetainingCapacity(end);
}

// Restores components that the state machine did not replace or remove.
fn restoreSuffix(self: *Parser) !void {
    if (self.suffix_query) |query| try self.setQuery(query.slice(self.suffix.items));
    if (self.suffix_fragment) |fragment| try self.setFragment(fragment.slice(self.suffix.items));
}

test "network url parser: replace components" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator);
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
