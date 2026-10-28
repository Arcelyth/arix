//! https://url.spec.whatwg.org/#url-representation
const Url = @This();
const std = @import("std");
const Host = @import("Host.zig");

pub const Component = struct {
    begin: usize = 0,
    len: usize = 0,

    pub fn fromBounds(begin: usize, end_offset: usize) Component {
        return .{
            .begin = begin,
            .len = end_offset - begin,
        };
    }

    pub fn end(self: Component) usize {
        return self.begin + self.len;
    }

    /// Returns this component's slice from the `source` full URL string.
    pub fn slice(self: Component, source: []const u8) []const u8 {
        return source[self.begin..self.end()];
    }
};

pub const Parsed = struct {
    scheme: Component = .{},
    username: ?Component = null,
    password: ?Component = null,
    host: ?Host = null,
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
