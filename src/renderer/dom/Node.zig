const Node = @This();

const std = @import("std");
const EventTarget = @import("EventTarget.zig");
const DomTypeId = @import("type.zig").DomTypeId;
const Document = @import("Document.zig");
const Element = @import("Element.zig");
const Text = @import("Text.zig");
const Comment = @import("Comment.zig");
const DocumentType = @import("DocumentType.zig");
const ProcessingInstruction = @import("ProcessingInstruction.zig");
const DocumentFragment = @import("DocumentFragment.zig");
const CustomElementRegistry = @import("CustomElementRegistry.zig");
const ln = @import("local_name");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;
const Tree = @import("../utils/tree.zig").Tree;

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
tree: Tree(Node) = .{},
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
        .node_doc = document,
    };
}

pub fn create(document: *Document) Node {
    // TODO:
    return init(.DOM_Element, document);
}

pub fn destroy(self: *Node, alloc: std.mem.Allocator) void {
    var child = self.first_child();
    while (child) |item| {
        const next = item.next_sibling();
        item.destroy(alloc);
        child = next;
    }

    switch (self.type_id) {
        .DOM_Element => {
            const element = self.downcast(Element);
            for (element.attrs.data.items) |*attr| attr.deinit();
            if (element.shadow_root) |shadow| {
                shadow.doc_frag.node.destroy(alloc);
                alloc.destroy(shadow);
            }
            if (element.temp_contents_owned) {
                const contents = element.temp_contents.?;
                contents.node.destroy(alloc);
                alloc.destroy(contents);
            }
            element.attrs.deinit();
            element.local_name.deinit();
            alloc.destroy(element);
        },
        .DOM_Text => {
            const text = self.downcast(Text);
            text.data.deinit();
            alloc.destroy(text);
        },
        .DOM_Comment => {
            const comment = self.downcast(Comment);
            comment.data.deinit();
            alloc.destroy(comment);
        },
        .DOM_DocumentType => {
            const doctype = self.downcast(DocumentType);
            doctype.name.deinit();
            doctype.public_id.deinit();
            doctype.system_id.deinit();
            alloc.destroy(doctype);
        },
        .DOM_ProcessingInstruction => {
            const pi = self.downcast(ProcessingInstruction);
            pi.target.deinit();
            pi.data.deinit();
            alloc.destroy(pi);
        },
        else => {},
    }
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

// ----- Tree implementation -----

/// The child must not already have a parent.
pub fn appendChild(self: *Node, child: *Node) void {
    self.tree.appendChild(child);
    if (child.type_id == .DOM_Element) child.downcast(Element).insertedIntoParent();
}

/// Insert `child` immediately before `reference`.
/// `reference` must be a child of this node.
pub fn insertBefore(
    self: *Node,
    child: *Node,
    reference: *Node,
) void {
    self.tree.insertBefore(child, reference);
    if (child.type_id == .DOM_Element) child.downcast(Element).insertedIntoParent();
}

/// Remove `child` from this node.
pub fn removeChild(
    self: *Node,
    child: *Node,
) void {
    self.tree.removeChild(child);
}

/// Remove this node from its parent.
pub fn remove(self: *Node) void {
    self.tree.remove();
}

pub inline fn parent(self: *const Node) ?*Node {
    return self.tree.parent;
}

pub inline fn first_child(self: *const Node) ?*Node {
    return self.tree.first_child;
}

pub inline fn last_child(self: *const Node) ?*Node {
    return self.tree.last_child;
}

pub inline fn next_sibling(self: *const Node) ?*Node {
    return self.tree.next_sibling;
}

pub inline fn prev_sibling(self: *const Node) ?*Node {
    return self.tree.prev_sibling;
}

// ----- -----

// https://dom.spec.whatwg.org/#concept-node-ensure-pre-insertion-validity
pub fn ensurePreInsertValidity(node: *Node, parent_node: *Node, child: ?*Node, exclude_children: []*Node) void {
    _ = node;
    _ = parent_node;
    _ = child;
    _ = exclude_children;
}

pub fn hasChild(self: *const Node, type_id: DomTypeId) bool {
    var child = self.first_child();

    while (child) |node| : (child = node.next_sibling())
        if (node.type_id == type_id) return true;

    return false;
}

pub const CloneOptions = struct {
    document: ?*Document = null,
    subtree: bool = false,
    parent: ?*Node = null,
    fallback_registry: ?*CustomElementRegistry = null,
};

// https://dom.spec.whatwg.org/#concept-node-clone
pub fn clone(self: *Node, options: CloneOptions) *Node {
    const document = options.document orelse self.node_doc;
    std.debug.assert(self.type_id != .DOM_Document or self.node_doc == document);
    const copy = self.cloneSingleNode(document, options.fallback_registry);

    // Run any cloning steps defined for node in other applicable specifications.
    // FIXME: This need to be extend for more dom types.
    if (self.type_id == .DOM_Element)
        self.downcast(Element).runCloningSteps(copy.downcast(Element), options.subtree);

    if (options.parent) |parent_node| parent_node.appendChild(copy);

    if (options.subtree) {
        var child = self.first_child();
        while (child) |node| : (child = node.next_sibling()) {
            _ = node.clone(.{
                .document = document,
                .subtree = true,
                .parent = copy,
                .fallback_registry = options.fallback_registry,
            });
        }
    }

    if (self.type_id == .DOM_Element) {
        const source = self.downcast(Element);
        if (source.shadow_root) |sd| {
            if (sd.clonable) {
                const target = copy.downcast(Element);
                target.attachShadowRoot(
                    sd.mode,
                    true,
                    sd.serialize,
                    sd.delegates_focus,
                    sd.slot_assignment,
                    sd.custom_element_registry,
                ) catch @panic("OutOfMemory");
                const target_shadow = target.shadow_root.?;
                target_shadow.declarative = sd.declarative;
                target_shadow.keep_cer_null = sd.keep_cer_null;

                var child = sd.doc_frag.node.first_child();
                while (child) |node| : (child = node.next_sibling())
                    _ = node.clone(.{ .document = document, .subtree = true, .parent = &target_shadow.doc_frag.node });
            }
        }
    }
    return copy;
}

// https://dom.spec.whatwg.org/#clone-a-single-node
fn cloneSingleNode(self: *Node, document: *Document, fallback_registry: ?*CustomElementRegistry) *Node {
    const copy = switch (self.type_id) {
        .DOM_Element => blk: {
            const source = self.downcast(Element);
            const registry = source.custom_element_registry orelse fallback_registry;
            const element = Element.create(
                document,
                source.local_name.clone(),
                source.ns,
                if (source.prefix) |prefix| prefix.clone() else null,
                source.is,
                false,
                registry,
            );
            for (source.attrs.data.items) |attr| {
                element.attrs.append(.{
                    .ns = attr.ns,
                    .prefix = if (attr.prefix) |prefix| prefix.clone() else null,
                    .local_name = attr.local_name.clone(),
                    .value = attr.value.clone(),
                    .element = null,
                }) catch @panic("OutOfMemory");
            }
            break :blk element.asNode();
        },
        .DOM_Text => Text.create(document, self.downcast(Text).data.clone()).asNode(),
        .DOM_Comment => Comment.create(document, self.downcast(Comment).data.clone()).asNode(),
        .DOM_DocumentType => blk: {
            const source = self.downcast(DocumentType);
            break :blk DocumentType.create(
                document,
                source.name.clone(),
                source.public_id.clone(),
                source.system_id.clone(),
            ).asNode();
        },
        .DOM_ProcessingInstruction => blk: {
            const source = self.downcast(ProcessingInstruction);
            break :blk ProcessingInstruction.create(
                document,
                source.target.clone(),
                source.data.clone(),
            ).asNode();
        },
        .DOM_Document => blk: {
            const source = self.downcast(Document);
            const result = Document.init(document.allocator);
            result.encoding = source.encoding;
            result.content_type = source.content_type;
            result.ty = source.ty;
            result.mode = source.mode;
            result.allow_decl_shadow_roots = source.allow_decl_shadow_roots;
            break :blk result.asNode();
        },
        .DOM_DocumentFragment => blk: {
            const fragment = document.allocator.create(DocumentFragment) catch @panic("OutOfMemory");
            fragment.* = DocumentFragment.init(document);
            break :blk &fragment.node;
        },
        else => unreachable,
    };
    return copy;
}

// https://dom.spec.whatwg.org/#concept-node-replace-all
pub fn replaceAll(node: ?*Node, parent_node: *Node) void {
    var removed_nodes: std.ArrayList(*Node) = .empty;
    defer removed_nodes.deinit(parent_node.node_doc.allocator);
    var child = parent_node.first_child();
    while (child) |item| : (child = item.next_sibling())
        removed_nodes.append(parent_node.node_doc.allocator, item) catch @panic("OutOfMemory");

    var added_nodes: std.ArrayList(*Node) = .empty;
    defer added_nodes.deinit(parent_node.node_doc.allocator);
    if (node) |replacement| {
        if (replacement.type_id == .DOM_DocumentFragment) {
            child = replacement.first_child();
            while (child) |item| : (child = item.next_sibling())
                added_nodes.append(parent_node.node_doc.allocator, item) catch @panic("OutOfMemory");
        } else {
            added_nodes.append(parent_node.node_doc.allocator, replacement) catch @panic("OutOfMemory");
        }
    }

    while (parent_node.first_child()) |item| {
        parent_node.removeChild(item);
    }

    if (node) |replacement| {
        if (replacement.type_id == .DOM_DocumentFragment) {
            while (replacement.first_child()) |item| {
                replacement.removeChild(item);
                parent_node.appendChild(item);
            }
        } else {
            replacement.remove();
            parent_node.appendChild(replacement);
        }
    }

    if (added_nodes.items.len != 0 or removed_nodes.items.len != 0)
        parent_node.queueTreeMutationRecord(added_nodes.items, removed_nodes.items, null, null);
}

// https://dom.spec.whatwg.org/#queue-a-tree-mutation-record
fn queueTreeMutationRecord(self: *Node, added_nodes: []const *Node, removed_nodes: []const *Node, previous_sibling: ?*Node, next_node: ?*Node) void {
    _ = self;
    _ = added_nodes;
    _ = removed_nodes;
    _ = previous_sibling;
    _ = next_node;
}

pub fn findDescendant(self: *Node, name: LocalTag) ?*Element {
    var child = self.first_child();
    while (child) |node| : (child = node.next_sibling()) {
        if (node.type_id == .DOM_Element) {
            const element = node.downcast(Element);
            if (element.ns == .NS_Html and element.local_name.is(name)) return element;
            if (node.findDescendant(name)) |found| return found;
        }
    }
    return null;
}
