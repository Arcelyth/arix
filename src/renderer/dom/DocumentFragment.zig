const DocumentFragment = @This();

const Node = @import("Node.zig");
const Document = @import("Document.zig");

node: Node,

pub const dom_type = .DOM_DocumentFragment;

pub fn init(doc: Document) DocumentFragment {
    return .{ .node = Node.init(.DOM_DocumentFragment, doc) };
}

pub fn fromNode(node: *Node) *DocumentFragment {
    return @fieldParentPtr("node", node);
}
