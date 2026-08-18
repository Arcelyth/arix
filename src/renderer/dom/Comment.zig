const Comment = @This();
const Node = @import("Node.zig");
const Document = @import("Document.zig");
const CharacterData = @import("CharacterData.zig");
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;

pub const dom_type = .DOM_Comment;

char_data: CharacterData,
data: StraleUtf8Global,

pub fn init(document: Document) Comment {
    return .{
        .char_data = CharacterData.init(document),
        .data = StraleUtf8Global.init(),
    };
}

pub fn create(document: Document, data: StraleUtf8Global) Comment {
    return .{
        .char_data = CharacterData.init(document),
        .data = data,
    };
}

pub inline fn asNode(self: *Comment) *Node {
    return &self.node;
}

pub fn fromNode(node: *Node) *Comment {
    const frag: *CharacterData = @fieldParentPtr("node", node);

    return @fieldParentPtr("char_data", frag);
}
