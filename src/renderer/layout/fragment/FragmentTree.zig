const FragmentTree = @This();

const std = @import("std");
const Fragment = @import("Fragment.zig");
const Rect = @import("../../geometry/Rect.zig");

/// The viewport establishes the initial containing block.
/// https://www.w3.org/TR/CSS2/visudet.html#containing-block-details
initial_containing_block: Rect,
root: ?*Fragment = null,

pub fn destroy(self: *FragmentTree, allocator: std.mem.Allocator) void {
    if (self.root) |root| root.destroy(allocator);
    self.root = null;
}
