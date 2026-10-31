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
}

/// https://url.spec.whatwg.org/#concept-basic-url-parser
pub fn parseUrl(self: *Parser, opts: ParseOpts) Url {
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
                    try self.setScheme();
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
            .no_scheme => {},
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

fn appendComponent(self: *Parser) !Url.Component {
    const start = self.output.items.len;
    try self.output.appendSlice(self.allocator, self.buffer.items);
    return Url.Component.fromBounds(start, self.output.items.len);
}

fn setScheme(self: *Parser) !void {
    self.parsed.scheme = try self.appendComponent();
    try self.appendOutput(':');
    self.parsed.path = .{ .begin = self.output.items.len };
}

fn scheme(self: *const Parser) []const u8 {
    return self.parsed.scheme.slice(self.output.items);
}

fn isSpecial(self: *const Parser) bool {
    return Url.special_scheme.has(self.scheme());
}

pub const ParserError = enum {
    InvalidUrlUnit,
    SpecialSchemeMissingFollowingSolidus,
};

pub fn handleError(self: *const Parser, err: ParserError) void {
    _ = self;
    _ = err;
}
