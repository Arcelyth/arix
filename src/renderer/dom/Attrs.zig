const Attrs = @This();

const Attr = @import("Attr.zig");
const std = @import("std");
const ln = @import("local_name");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;

allocator: std.mem.Allocator,
data: std.ArrayList(Attr),

pub fn init(alloc: std.mem.Allocator) Attrs {
    return .{
        .allocator = alloc,
        .data = .empty,
    };
}

pub fn deinit(self: *Attrs) void {
    self.data.deinit(self.alloc);
}

pub fn append(self: *Attrs, item: Attr) !void {
    try self.data.append(item);
}

pub fn getFromLocalName(self: *const Attrs, target: LocalTag) ?*Attr {
    for (self.data.items) |*attr| {
        if (attr.local_name.is(target)) return attr;
    }
    return null;
}
