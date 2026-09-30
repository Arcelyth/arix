const StyledNode = @This();

const std = @import("std");
const Node = @import("../dom/Node.zig");
const Element = @import("../dom/Element.zig");
const matching = @import("matching.zig");
const cascade = @import("cascade.zig");
const MatchedRule = @import("cascade/MatchedRule.zig").MatchedRule;
const PreparedStylesheet = @import("PreparedStylesheet.zig");
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

/// Build a StyledNode tree, return it's root.
pub fn build(
    allocator: std.mem.Allocator,
    root: *Element,
    stylesheets: []const PreparedStylesheet,
    context: *const ComputedStyle.Context,
) !*StyledNode {
    var matched_rules: std.ArrayList(MatchedRule) = .empty;
    defer matched_rules.deinit(allocator);

    const result = try allocator.create(StyledNode);
    result.* = StyledNode.init(root.asNode(), .{});
    errdefer result.destroy(allocator);

    var current = result;
    walk: while (true) {
        matched_rules.clearRetainingCapacity();
        if (current.node.type_id == .DOM_Element) {
            const element = current.node.downcast(Element);
            if (element.shadow_root != null) @panic("TODO: shadow-tree styling");

            for (stylesheets) |stylesheet| {
                try matching.collectMatchedRules(
                    allocator,
                    stylesheet.rules,
                    element,
                    &matched_rules,
                );
            }
        }

        const winners = cascade.cascade(matched_rules.items);
        const parent_node = if (current.parent()) |node| &node.style else null;
        current.style = ComputedStyle.compute(&winners, parent_node, context);

        // DFS.
        var next = current.node.first_child();
        while (true) {
            while (next) |node| : (next = node.next_sibling()) {
                if (node.type_id != .DOM_Element and node.type_id != .DOM_Text) continue;

                const child = try allocator.create(StyledNode);
                child.* = StyledNode.init(node, .{});
                current.appendChild(child);
                current = child;
                continue :walk;
            }
            if (current == result) return result;
            next = current.node.next_sibling();
            current = current.parent().?;
        }
    }
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
