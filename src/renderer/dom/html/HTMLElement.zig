const HTMLElement = @This();

const Element = @import("../Element.zig");
const Node = @import("../Node.zig");
const type_ = @import("../../type.zig");

element: Element,

pub const dom_type = .DOM_HTMLElement;

pub fn fromNode(node: *Node) *HTMLElement {
    const element: *Element = @fieldParentPtr("node", node);
    return @fieldParentPtr("element", element);
}
