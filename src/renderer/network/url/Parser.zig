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

/// https://url.spec.whatwg.org/#concept-basic-url-parser
pub fn parseUrl(self: *Parser, opts: ParseOpts) Url {
    if (std.mem.indexOfAny(u8, self.input.asSlice(), "\t\n\r") != null)
        self.handleError(.InvalidUrlUnit);

    var state = .scheme_start;
    const encoding = encodings.getOutputEncoding(opts.encoding orelse .utf8);
    var buffer: std.ArrayList(u8) = .empty;
    const at_sign_seen = false;
    const inside_brackets = false;
    const password_token_seen = false;
    self.input.chars.i = 0;

    _ = encoding;
    _ = at_sign_seen;
    _ = inside_brackets;
    _ = password_token_seen;

    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    while (true) {
        const before = self.input;
        const cp = self.input.next();
        switch (state) {
            // https://url.spec.whatwg.org/#scheme-start-state
            .scheme_start => {
                if (cp != null and ascii.isAsciiAlpha(cp.?)) {
                    try buffer.append(allocator, std.ascii.toLower(@intCast(cp.?)));
                    state = .scheme;
                } else {
                    state = .no_scheme;
                    self.input = before;
                }
            },
            // https://url.spec.whatwg.org/#scheme-state
            .scheme => {},
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

pub const ParserError = enum {
    InvalidUrlUnit,
};

pub fn handleError(self: *const Parser, err: ParserError) void {
    _ = self;
    _ = err;
}
