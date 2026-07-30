const Node = @This();

const std = @import("std");

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

node_type: NodeType,
