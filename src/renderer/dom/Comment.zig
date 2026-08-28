const Comment = @This();
const Node = @import("Node.zig");
const Document = @import("Document.zig");
const CharacterData = @import("CharacterData.zig");
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;

pub const dom_type = .DOM_Comment;

char_data: CharacterData,
data: StraleUtf8Global,

pub fn init(document: *Document) Comment {
    var comment: Comment = .{
        .char_data = CharacterData.init(document),
        .data = StraleUtf8Global.init(),
    };
    // FIXME: Might need put in init's parameter.
    comment.char_data.node.type_id = dom_type;
    return comment;
}

pub fn create(document: *Document, data: StraleUtf8Global) *Comment {
    const comment = document.allocator.create(Comment) catch @panic("out of memory");
    comment.* = .{
        .char_data = CharacterData.init(document),
        .data = data,
    };
    comment.char_data.node.type_id = dom_type;
    return comment;
}

pub inline fn asNode(self: *Comment) *Node {
    return &self.char_data.node;
}

pub fn fromNode(node: *Node) *Comment {
    const frag: *CharacterData = @fieldParentPtr("node", node);

    return @fieldParentPtr("char_data", frag);
}
