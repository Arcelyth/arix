const Document = @This();

const Namespace = @import("namespace.zig").Namespace;
const Node = @import("Node.zig");
const CustomElementRegistry = @import("CustomElementRegistry.zig");
const std = @import("std");
const token = @import("../html/tokenizer/token.zig");
const Encoding = @import("../html/encoding/encoding.zig").Encoding;
const ln = @import("local_name");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;

pub const DocMode = enum {
    DM_NoQuirks,
    DM_Quirks,
    DM_LimitedQuirks,
};

pub const DocType = enum {
    DT_Xml,
    DT_Html,
};

node: Node,
// FIXME: Decide where to place the allocator.
allocator: std.mem.Allocator,
encoding: Encoding,
content_type: []const u8,
// TODO:
// url:
// origin: ,
ty: DocType,
mode: DocMode,
// Allow declarative shadow roots.
allow_decl_shadow_roots: bool,
custom_element_registry: ?*CustomElementRegistry,
// Stands for throw-on-dynamic-markup-insertion counter.
todmi_counter: usize,
// FIXME: This field might need to store in parser.
parser_cannot_change_the_mode: bool,
scripting_enabled: bool,

pub const dom_type = .DOM_Document;

pub fn init(alloc: std.mem.Allocator) *Document {
    const document = alloc.create(Document) catch @panic("TODO");

    document.* = .{
        .node = undefined,
        .allocator = alloc,
        .encoding = .utf8,
        .content_type = "application/xml",
        .ty = .DT_Xml,
        .mode = .DM_NoQuirks,
        .allow_decl_shadow_roots = false,
        .custom_element_registry = null,
        .todmi_counter = 0,
        .parser_cannot_change_the_mode = false,
        .scripting_enabled = true,
    };

    document.node = Node.init(.DOM_Document, document);

    return document;
}

pub fn destroy(self: *Document, alloc: std.mem.Allocator) void {
    var child = self.node.first_child;
    while (child) |node| {
        const next = node.next_sibling;
        node.destroy(alloc);
        child = next;
    }
    alloc.destroy(self);
}

pub inline fn asNode(self: *Document) *Node {
    return &self.node;
}

pub fn fromNode(node: *Node) *Document {
    return @fieldParentPtr("node", node);
}

pub fn isIframeSrcdocDocument(self: *Document) bool {
    _ = self;
    // TODO;
    return false;
}
