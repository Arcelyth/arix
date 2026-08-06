const Node = @This();

const std = @import("std");
const EventTarget = @import("EventTarget.zig");
const DomTypeId = @import("type.zig").DomTypeId;
const Document = @import("Document.zig");

/// For interface.
pub const NodeType = enum(u4) {
    ElementNode = 1,
    AttributeNode,
    TextNode,
    CDATASectionNode,
    EntityReferenceNode, // legacy
    EntityNode, // legacy
    ProcessingInstructionNode,
    CommentNode,
    DocumentNode,
    DocumentTypeNode,
    DocumentFragmentNode,
    NotationNode,
};

event_target: EventTarget,
/// The runtime type identifier of this DOM object.
type_id: DomTypeId,
parent: ?*Node,
first_child: ?*Node,
last_child: ?*Node,
next_sibling: ?*Node,
prev_sibling: ?*Node,
// Associated node document.
// Maybe need to remove '?'.
node_doc: ?*Document,

/// The compile-time type identifier of Node.
pub const dom_type = .DOM_Node;

pub fn init(type_id: DomTypeId, document: ?*Document) Node {
    return .{
        .event_target = EventTarget.init(),
        .type_id = type_id,
        .parent = null,
        .first_child = null,
        .last_child = null,
        .next_sibling = null,
        .prev_sibling = null,
        .node_doc = document,
    };
}

/// Attempts to downcast this Node into a more specific DOM type.
/// The target type `T` must provide a `fromNode` function that converts a
/// `*Node` pointer into a pointer to the corresponding DOM object.
pub inline fn downcast(self: *Node, comptime T: type) *T {
    if (self.type_id != T.dom_type) @panic("Downcast failed: two types are not compatible.");

    return T.fromNode(self);
}

pub inline fn isA(self: *Node, type_id: DomTypeId) bool {
    if (self.type_id == type_id) return true;
    return false;
}
