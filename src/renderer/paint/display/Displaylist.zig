const DisplayList = @This();

const std = @import("std");
const DisplayItem = @import("display_item.zig").DisplayItem;
const fragment = @import("../../layout/fragment.zig");
const Fragment = fragment.Fragment;
const FragmentTree = fragment.FragmentTree;

items: std.ArrayList(DisplayItem) = .empty,

pub fn deinit(self: *DisplayList, allocator: std.mem.Allocator) void {
    self.items.deinit(allocator);
    self.* = .{};
}

pub fn buildDisplayList(allocator: std.mem.Allocator, tree: *const FragmentTree) !DisplayList {
    _ = allocator;
    _ = tree;
    @panic("TODO");
}
