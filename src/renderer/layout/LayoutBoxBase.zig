const LayoutBoxBase = @This();

const std = @import("std");
const Element = @import("../dom/Element.zig");
const ComputedStyle = @import("../style/computed/ComputedStyle.zig");
const Display = @import("../css/values/computed/display.zig").Display;
const registry = @import("../css/properties/registry.zig");
const Fragment = @import("fragment.zig").Fragment;

pub const Source = union(enum) {
    principal: *const Element,
    anonymous,
    // FIXME:
    marker: *const Element,
};

source: Source,
style: ComputedStyle,
/// Geometry produced later by layout; not part of the computed CSS values.
fragments: std.ArrayList(Fragment) = .empty,

pub fn deinit(self: *LayoutBoxBase, allocator: std.mem.Allocator) void {
    self.fragments.deinit(allocator);
}
