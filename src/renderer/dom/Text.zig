const Text = @This();
const Node = @import("Node.zig");
const Document = @import("Document.zig");
const CharacterData = @import("CharacterData.zig");
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;

pub const dom_type = .DOM_Text;

char_data: CharacterData,
data: StraleUtf8Global,

pub fn init(document: *Document) Text {
    var text: Text = .{
        .char_data = CharacterData.init(document),
        .data = StraleUtf8Global.init(),
    };
    text.char_data.node.type_id = dom_type;
    return text;
}

pub fn create(document: *Document, data: StraleUtf8Global) *Text {
    const text = document.allocator.create(Text) catch @panic("out of memory");
    text.* = .{
        .char_data = CharacterData.init(document),
        .data = data,
    };
    text.char_data.node.type_id = dom_type;
    return text;
}

pub inline fn asNode(self: *Text) *Node {
    return &self.char_data.node;
}

pub fn fromNode(node: *Node) *Text {
    const frag: *CharacterData = @fieldParentPtr("node", node);

    return @fieldParentPtr("char_data", frag);
}
