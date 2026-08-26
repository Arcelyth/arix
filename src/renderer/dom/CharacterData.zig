const CharacterData = @This();
const Node = @import("Node.zig");
const Document = @import("Document.zig");

pub const dom_type = .DOM_CharacteData;

node: Node,

pub fn init(document: *Document) CharacterData {
    return .{
        .node = Node.init(dom_type, document),
    };
}

pub inline fn asNode(self: *CharacterData) *Node {
    return &self.node;
}

pub fn fromNode(node: *Node) *CharacterData {
    return @fieldParentPtr("node", node);
}
