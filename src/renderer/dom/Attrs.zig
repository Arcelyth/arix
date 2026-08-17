const Attrs = @This();

const Attr = @import("Attr.zig");
const std = @import("std");

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
