const StyledNode = @This();

const Node = @import("../dom/Node.zig");
const Stylesheet = @import("../css/syntax/parsing_results.zig").Stylesheet;
const ComputedStyle = @import("computed/ComputedStyle.zig");

node: *Node,
style: ComputedStyle,

parent: ?*StyledNode = null,
first_child: ?*StyledNode = null,
last_child: ?*StyledNode = null,
next_sibling: ?*StyledNode = null,
prev_sibling: ?*StyledNode = null,

pub fn init(node: *Node, style: ComputedStyle) StyledNode {
    return .{
        .node = node,
        .style = style,
    };
}
