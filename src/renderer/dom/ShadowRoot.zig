const ShadowRoot = @This();

const std = @import("std");
const DocumentFragment = @import("DocumentFragment.zig");
const CustomElementRegistry = @import("CustomElementRegistry.zig");
const Node = @import("Node.zig");
const Document = @import("Document.zig");

pub const ShadowRootMode = enum {
    SR_Open,
    SR_Closed,
};

pub const ShadowRootSlotAssignment = enum {
    SR_Manual,
    SR_Named,
};

// Inherited Document Fragment.
doc_frag: DocumentFragment,
custom_element_registry: ?*CustomElementRegistry,
// host:
mode: ShadowRootMode,
delegates_focus: bool,
// Whether available to element internals.
available: bool,
declarative: bool,
slot_assignment: ShadowRootSlotAssignment,
clonable: bool,
serialize: bool,
// Whether keep custom element registry null.
keep_cer_null: bool,

pub const dom_type = .DOM_ShadowRoot;

pub fn init(doc: Document) ShadowRoot {
    return .{
        .doc_frag = DocumentFragment.init(doc),
        .custom_element_registry = null,
        .mode = .SR_Open,
        .delegates_focus = false,
        .available = false,
        .declarative = false,
        .slot_assignment = .SR_Manual,
        .clonable = false,
        .serialize = false,
        .keep_cer_null = false,
    };
}

pub fn fromNode(node: *Node) *ShadowRoot {
    const frag: *DocumentFragment = @fieldParentPtr("node", node);

    return @fieldParentPtr("doc_frag", frag);
}
