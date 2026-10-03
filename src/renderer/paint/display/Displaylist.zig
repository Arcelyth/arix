const DisplayList = @This();

const std = @import("std");
const DisplayItem = @import("display_item.zig").DisplayItem;

items: std.ArrayList(DisplayItem) = .empty,

pub fn deinit(self: *DisplayList, allocator: std.mem.Allocator) void {
    self.items.deinit(allocator);
    self.* = .{};
}
