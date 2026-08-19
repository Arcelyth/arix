const ProcessingInstruction = @This();
const Node = @import("Node.zig");
const Document = @import("Document.zig");
const CharacterData = @import("CharacterData.zig");
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;

pub const dom_type = .DOM_ProcessingInstruction;

char_data: CharacterData,
target: StraleUtf8Global,
// attr_map:
data: StraleUtf8Global,

pub fn init(document: Document) ProcessingInstruction {
    return .{
        .char_data = CharacterData.init(document),
        .data = StraleUtf8Global.init(),
    };
}

pub fn create(document: Document, target: StraleUtf8Global, data: StraleUtf8Global) ProcessingInstruction {
    return .{
        .char_data = CharacterData.init(document),
        .target = target,
        .data = data,
    };
}

pub inline fn asNode(self: *ProcessingInstruction) *Node {
    return &self.node;
}

pub fn fromNode(node: *Node) *ProcessingInstruction {
    const frag: *CharacterData = @fieldParentPtr("node", node);

    return @fieldParentPtr("char_data", frag);
}
