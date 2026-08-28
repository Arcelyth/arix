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

pub fn init(document: *Document) ProcessingInstruction {
    var pi: ProcessingInstruction = .{
        .char_data = CharacterData.init(document),
        .target = StraleUtf8Global.init(),
        .data = StraleUtf8Global.init(),
    };
    pi.char_data.node.type_id = dom_type;
    return pi;
}

pub fn create(document: *Document, target: StraleUtf8Global, data: StraleUtf8Global) *ProcessingInstruction {
    const pi = document.allocator.create(ProcessingInstruction) catch @panic("out of memory");
    pi.* = .{
        .char_data = CharacterData.init(document),
        .target = target,
        .data = data,
    };
    pi.char_data.node.type_id = dom_type;
    return pi;
}

pub inline fn asNode(self: *ProcessingInstruction) *Node {
    return &self.char_data.node;
}

pub fn fromNode(node: *Node) *ProcessingInstruction {
    const frag: *CharacterData = @fieldParentPtr("node", node);

    return @fieldParentPtr("char_data", frag);
}
