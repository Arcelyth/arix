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
node_doc: *Document,

/// The compile-time type identifier of Node.
pub const dom_type = .DOM_Node;

// Document should not be null except when initializing Document.
pub fn init(type_id: DomTypeId, document: *Document) Node {
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

/// The child must not already have a parent.
pub fn appendChild(self: *Node, child: *Node) void {
    child.parent = self;
    child.prev_sibling = self.last_child;
    child.next_sibling = null;

    if (self.last_child) |last|
        last.next_sibling = child
    else
        // The node had no children.
        self.first_child = child;

    self.last_child = child;
}

/// Insert `child` immediately before `reference`.
/// `reference` must be a child of this node.
pub fn insertBefore(
    self: *Node,
    child: *Node,
    reference: *Node,
) void {
    std.debug.assert(reference.parent == self);

    child.parent = self;
    child.next_sibling = reference;
    child.prev_sibling = reference.prev_sibling;

    if (reference.prev_sibling) |prev|
        prev.next_sibling = child
    else
        self.first_child = child;

    reference.prev_sibling = child;
}

/// Remove `child` from this node.
pub fn removeChild(
    self: *Node,
    child: *Node,
) void {
    std.debug.assert(child.parent == self);

    if (child.prev_sibling) |prev|
        prev.next_sibling = child.next_sibling
    else
        self.first_child = child.next_sibling;

    if (child.next_sibling) |next|
        next.prev_sibling = child.prev_sibling
    else
        self.last_child = child.prev_sibling;

    child.parent = null;
    child.prev_sibling = null;
    child.next_sibling = null;
}

/// Remove this node from its parent.
pub fn remove(self: *Node) void {
    const parent = self.parent orelse return;
    parent.removeChild(self);
}

// https://dom.spec.whatwg.org/#concept-node-ensure-pre-insertion-validity
pub fn ensurePreInsertValidity(node: *Node, parent: *Node, child: ?*Node, exclude_children: []*Node) void {
    _ = node;
    _ = parent;
    _ = child;
    _ = exclude_children;
}

pub fn hasChild(self: *const Node, type_id: DomTypeId) bool {
    var child = self.first_child;

    while (child) |node| : (child = node.next_sibling)
        if (node.type_id == type_id) return true;

    return false;
}
