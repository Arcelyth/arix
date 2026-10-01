const LayoutBox = @This();

const std = @import("std");
const Tree = @import("../utils/tree.zig").Tree;
const Fragment = @import("fragment.zig").Fragment;
const StyledNode = @import("../style/StyledNode.zig");

/// Formatting roles.
pub const Kind = enum {
    block,
    flow_root,
    @"inline",
    inline_block,
    text,
    marker,
};

pub const Source = union(enum) {
    principal: *const StyledNode,
    /// An anonymous box is a box that is not associated with any element
    anonymous,
    marker: *const StyledNode,
};

kind: Kind,
source: Source,
/// Layout output, not computed CSS values. Empty until a formatting pass runs.
/// One source box can produce several fragments when fragmentation is supported.
fragments: std.ArrayList(Fragment),
tree: Tree(LayoutBox) = .{},

// ----- Tree implementation -----
pub fn appendChild(self: *LayoutBox, child: *LayoutBox) void {
    self.tree.appendChild(child);
}

pub fn insertBefore(self: *LayoutBox, child: *LayoutBox, reference: *LayoutBox) void {
    self.tree.insertBefore(child, reference);
}

pub fn removeChild(self: *LayoutBox, child: *LayoutBox) void {
    self.tree.removeChild(child);
}

pub fn remove(self: *LayoutBox) void {
    self.tree.remove();
}

pub inline fn parent(self: *const LayoutBox) ?*LayoutBox {
    return self.tree.parent;
}

pub inline fn first_child(self: *const LayoutBox) ?*LayoutBox {
    return self.tree.first_child;
}

pub inline fn last_child(self: *const LayoutBox) ?*LayoutBox {
    return self.tree.last_child;
}

pub inline fn next_sibling(self: *const LayoutBox) ?*LayoutBox {
    return self.tree.next_sibling;
}

pub inline fn prev_sibling(self: *const LayoutBox) ?*LayoutBox {
    return self.tree.prev_sibling;
}
