const Node = @This();

const std = @import("std");
const EventTarget = @import("EventTarget.zig");
const DomTypeId = @import("type.zig").DomTypeId;

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

/// The compile-time type identifier of Node.
pub const dom_type = .DOM_Node;

pub fn init(type_id: DomTypeId) Node {
    return .{
        .event_target = EventTarget.init(),
        .type_id = type_id,
        .parent = null,
        .first_child = null,
        .last_child = null,
        .next_sibling = null,
        .prev_sibling = null,
    };
}

/// Attempts to downcast this Node into a more specific DOM type.
pub fn downcast(self: *Node, comptime T: type) *T {
    if (self.type_id != T.dom_type) @panic("Downcast failed: two types are not compatible.");

    return @fieldParentPtr("node", self);
}
