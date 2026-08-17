const Document = @This();

const Namespace = @import("namespace.zig").Namespace;
const Node = @import("Node.zig");
const CustomElementRegistry = @import("CustomElementRegistry.zig");
const std = @import("std");
const token = @import("../html/tokenizer/token.zig");
const ln = @import("local_name");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;

node: Node,
custom_element_registry: ?*CustomElementRegistry,
// Stands for throw-on-dynamic-markup-insertion counter.
todmi_counter: usize,

pub const dom_type = .DOM_Document;

pub fn init() Document {
    return .{
        .node = Node.init(.DOM_Document, null),
        .custom_element_registry = null,
        .todmi_counter = 0,
    };
}

pub inline fn asNode(self: *Document) *Node {
    return &self.node;
}

pub fn fromNode(node: *Node) *Document {
    return @fieldParentPtr("node", node);
}
