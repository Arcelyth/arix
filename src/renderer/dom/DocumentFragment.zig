const DocumentFragment = @This();

const Node = @import("Node.zig");
const Document = @import("Document.zig");
const Element = @import("Element.zig");

node: Node,
host: ?*Element,

pub const dom_type = .DOM_DocumentFragment;

pub fn init(doc: *Document) DocumentFragment {
    return .{ .node = Node.init(dom_type, doc), .host = null };
}

pub fn fromNode(node: *Node) *DocumentFragment {
    return @fieldParentPtr("node", node);
}
