const Host = @This();
const Component = @import("Url.zig").Component;

pub const HostKind = enum {
    domain,
    ipv4,
    ipv6,
    @"opaque",
};

range: Component,
kind: HostKind,
