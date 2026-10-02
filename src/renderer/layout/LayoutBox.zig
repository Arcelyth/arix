const LayoutBox = @This();

const std = @import("std");
const Tree = @import("../utils/tree.zig").Tree;
const Fragment = @import("fragment.zig").Fragment;
const Element = @import("../dom/Element.zig");
const ComputedStyle = @import("../style/computed/ComputedStyle.zig");
const Display = @import("../css/values/computed/display.zig").Display;
const registry = @import("../css/properties/registry.zig");
const TextSequence = @import("TextSequence.zig");

/// A box tree contains boxes and text sequences. Text sequences have no display
/// type; a box's formatting behavior comes from its computed display value.
pub const Content = union(enum) {
    box: Box,
    text: TextSequence,
};

pub const Box = struct {
    /// Box origin, not its formatting model. Elements are borrowed; anonymous
    /// boxes have no originating element. Marker generation is still TODO.
    /// https://www.w3.org/TR/css-display-3/#intro
    pub const Source = union(enum) {
        principal: *const Element,
        anonymous,
        // FIXME:
        marker: *const Element,
    };

    source: Source,
    style: ComputedStyle,
};

content: Content,
/// Layout output. Empty until a formatting pass runs.
/// One source box can produce several fragments when fragmentation is supported.
fragments: std.ArrayList(Fragment) = .empty,
tree: Tree(LayoutBox) = .{},

pub fn init(content: Content) LayoutBox {
    return .{ .content = content };
}

/// Destroy owned tree entries and fragments without touching borrowed DOM or
/// styled nodes. Computed box styles are plain values and need no teardown.
pub fn destroy(self: *LayoutBox, allocator: std.mem.Allocator) void {
    self.remove();
    var current = self;
    while (true) {
        if (current.first_child()) |child| {
            current = child;
            continue;
        }
        const parent_node = current.parent();
        current.remove();
        current.fragments.deinit(allocator);
        allocator.destroy(current);
        current = parent_node orelse return;
    }
}

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


