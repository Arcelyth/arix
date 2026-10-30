const Parser = @This();
const std = @import("std");
const Url = @import("Url.zig");
const encoding = @import("../../encoding.zig");
const Encoding = encoding.Encoding;
const ascii = @import("../../utils/ascii.zig");

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
input: []const u8,

pub const ParseOpts = struct {
    base: ?*const Url = null,
    encoding: ?Encoding = .utf8,
};

pub fn init(allocator: std.mem.Allocator, input: []const u8) Parser {
    return .{
        .allocator = allocator,
        .input = input,
    };
}

/// https://url.spec.whatwg.org/#concept-basic-url-parser
pub fn parseUrl(self: *const Parser, opts: ParseOpts) void {
    _ = self;
    _ = opts;
}

pub const ParserError = enum {
    InvalidUrlUnit,
};

pub fn handleError(self: *const Parser, err: ParserError) void {
    _ = self;
    _ = err;
}
