const StyledNode = @This();

const Node = @import("../dom/Node.zig");
const Stylesheet = @import("../css/syntax/parsing_results.zig").Stylesheet;
const ComputedStyle = @import("computed/ComputedStyle.zig");
const Tree = @import("../utils/tree.zig").Tree;

node: *Node,
style: ComputedStyle,

tree: Tree(StyledNode) = .{},

pub fn init(node: *Node, style: ComputedStyle) StyledNode {
    return .{
        .node = node,
        .style = style,
    };
}

// ----- Tree implementation -----

/// The child must not already have a parent.
pub fn appendChild(self: *StyledNode, child: *StyledNode) void {
    self.tree.appendChild(child);
}

/// Insert `child` immediately before `reference`.
/// `reference` must be a child of this node.
pub fn insertBefore(
    self: *StyledNode,
    child: *StyledNode,
    reference: *StyledNode,
) void {
    self.tree.insertBefore(child, reference);
}

/// Remove `child` from this node.
pub fn removeChild(
    self: *StyledNode,
    child: *StyledNode,
) void {
    self.tree.removeChild(child);
}

/// Remove this node from its parent.
pub fn remove(self: *StyledNode) void {
    self.tree.remove();
}

pub inline fn parent(self: *const StyledNode) ?*StyledNode {
    return self.tree.parent;
}

pub inline fn first_child(self: *const StyledNode) ?*StyledNode {
    return self.tree.first_child;
}

pub inline fn last_child(self: *const StyledNode) ?*StyledNode {
    return self.tree.last_child;
}

pub inline fn next_sibling(self: *const StyledNode) ?*StyledNode {
    return self.tree.next_sibling;
}

pub inline fn prev_sibling(self: *const StyledNode) ?*StyledNode {
    return self.tree.prev_sibling;
}

// ----- -----
