const DocumentType = @This();

const Node = @import("Node.zig");
const std = @import("std");
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;
const Document = @import("Document.zig");

node: Node,
name: StraleUtf8Global,
public_id: StraleUtf8Global,
system_id: StraleUtf8Global,

pub const dom_type = .DOM_DocumentType;

pub fn init() DocumentType {
    return .{
        .node = Node.init(dom_type, null),
        .name = StraleUtf8Global.init(),
        .public_id = StraleUtf8Global.init(),
        .system_id = StraleUtf8Global.init(),
    };
}

pub fn create(doc: *Document, name: StraleUtf8Global, public_id: StraleUtf8Global, system_id: StraleUtf8Global) DocumentType {
    return .{
        .node = Node.init(dom_type, doc),
        .name = name,
        .public_id = public_id,
        .system_id = system_id,
    };
}

pub inline fn asNode(self: *DocumentType) *Node {
    return &self.node;
}

pub fn fromNode(node: *Node) *DocumentType {
    return @fieldParentPtr("node", node);
}
