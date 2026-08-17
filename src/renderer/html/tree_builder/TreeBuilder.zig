const TreeBuilder = @This();

const std = @import("std");
const token_ = @import("../tokenizer/token.zig");
const Token = token_.Token;
const Attribute = token_.Attribute;
const Node = @import("../../dom/Node.zig");
const Element = @import("../../dom/Element.zig");
const Text = @import("../../dom/Text.zig");
const Document = @import("../../dom/Document.zig");
const CustomElementRegistry = @import("../../dom/CustomElementRegistry.zig");
const CustomElementDefinition = @import("../../dom/CustomElementDefinition.zig");
const Namespace = @import("../../dom/namespace.zig").Namespace;
const ln = @import("local_name");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;

const InsertionMode = enum {
    InitialMode,
    BeforeHtmlMode,
    BeforeHeadMode,
    InHeadMode,
    InHeadNoscriptMode,
    AfterHeadMode,
    InBodyMode,
    TextMode,
    InTableMode,
    InTableTextMode,
    InCaptionMode,
    InColumnGroupMode,
    InTableBodyMode,
    InRowMode,
    InCellMode,
    InTemplateMode,
    AfterBodyMode,
    InFramesetMode,
    AfterFramesetMode,
    AfterAfterBodyMode,
    AfterAfterFramesetMode,
};

const InsertionLocation = union {
    last_child: *Element,
    before_child: *Element,
    parent_before_child: struct {
        parent: *Element,
        before_child: *Element,
    },

    pub fn getParent(self: *InsertionLocation) *Element {
        return switch (self) {
            .last_child => |parent| parent,

            .before_child => |before| blk: {
                const p = before.asNode().parent orelse @panic("before_child has no parent");
                break :blk p.downcast(Element);
            },

            .parent_before_child => |loc| loc.parent,
        };
    }

    pub fn beforeNode(self: InsertionLocation) ?*Node {
        const before = switch (self) {
            .last_child => return null,
            .before_child => |node| node,
            .parent_before_child => |loc| loc.before_child,
        };

        const n = before.asNode();

        return n.prev_sibling;
    }

    pub fn beforeChild(self: InsertionLocation) ?*Element {
        return switch (self) {
            .last_child => null,
            .before_child => |node| node,
            .parent_before_child => |loc| loc.before_child,
        };
    }
};

const ScriptingMode = enum {
    Normal,
    Disabled,
    Inert,
    Fragment,
};

allocator: std.mem.Allocator,
open_elements: std.ArrayList(*Element),
// InsertionMode
insert_mode: InsertionMode,
// Original Insertion Mode
orig_insert_mode: InsertionMode,
// Template Insertion Mode
temp_insert_modes: std.ArrayList(InsertionMode),
// Whether the parser was created as part of the
// HTML fragment parsing algorithm.
fragment_case: bool,
scripting_mode: ScriptingMode,
foster_parenting: bool,
frameset_ok: bool,

pub fn init(alloc: std.mem.Allocator, fragment_case: bool) TreeBuilder {
    return TreeBuilder{
        .allocator = alloc,
        .open_elements = .empty,
        .insert_mode = .InitialMode,
        .orig_insert_mode = .InitialMode,
        .temp_insert_modes = .empty,
        .fragment_case = fragment_case,
        .scripting_mode = .Normal,
        .foster_parenting = false,
        .frameset_ok = false,
    };
}

pub fn deinit(self: *TreeBuilder) void {
    self.open_elements.deinit(self.allocator);
}

/// Implement TokenIngester.
pub fn handleToken(self: *TreeBuilder, tk: Token) void {
    // Dispatch token.
    if (self.isForeign(tk)) {
        self.processTokenForeign(tk);
    } else {
        self.processToken(tk);
    }
}

// https://html.spec.whatwg.org/#tree-construction-dispatcher
pub fn isForeign(self: *const TreeBuilder, tk: Token) bool {
    if (self.open_elements.items.len == 0 or std.meta.activeTag(tk) == .EofToken) return false;
    const cur_el = self.adjustedCurrentNode();

    if (cur_el.ns == .NS_Html) return false;

    if (cur_el.isMathMLTextIntegrationPoint()) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag and !tag.name.eql(.mglyph) and !tag.name.eql(.malignmark)) return false;
            },
            .CharacterToken => return false,
            else => {},
        }
    }

    if (cur_el.isMathMLAnnotationXml()) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag and tag.name.eql(.svg)) return false;
            },
            else => {},
        }
    }

    if (cur_el.isHtmlIntegrationPoint()) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag) return false;
            },
            .CharacterToken => return false,
        }
    }

    return true;
}

pub fn processToken(self: *const TreeBuilder, tk: Token) void {
    _ = self;
    _ = tk;
}

pub fn processTokenForeign(self: *const TreeBuilder, tk: Token) void {
    _ = self;
    _ = tk;
}

pub fn adjustedCurrentNode(self: *TreeBuilder) *Node {
    if (self.open_elements.getLastOrNull()) |*node| return &node else @panic("Stack of open elements is empty.");
}

// https://html.spec.whatwg.org/#appropriate-place-for-inserting-a-node
pub fn appropriatePlaceForInsertion(self: *TreeBuilder, override_target: ?*Element) InsertionLocation {
    const target = override_target orelse self.currentNode();
    if (self.foster_parenting and target.in(&.{ .table, .tbody, .tfoot, .thead, .tr })) {
        const open_elements = self.open_elements;
        var last_table: ?*Element = null;
        var last_table_pos: usize = 0;
        var idx = open_elements.items.len;
        blk: while (idx > 0) {
            idx -= 1;
            if (open_elements.items[idx].local_name.is(.table)) {
                last_table = self.open_elements.items[idx];
                last_table_pos = idx;
                break :blk;
            }
            if (open_elements.items[idx].local_name.is(.template)) {
                return .{ .last_child = self.open_elements.items[idx] };
            }
        }

        if (last_table) |table| {
            if (table.asNode().parent) |p|
                return .{ .parent_before_child = .{
                    .parent = p.downcast(Element),
                    .before_child = table,
                } }
            else if (last_table_pos > 0)
                return .{ .last_child = self.open_elements.items[last_table_pos - 1] }
            else
                @panic("This should never happen: last_table_pos <= 0");
        } else {
            return .{ .last_child = self.htmlElement() orelse target };
        }
    }
    return .{ .last_child = target };
}

// https://html.spec.whatwg.org/#create-an-element-for-the-token
pub fn createElementForToken(self: *TreeBuilder, tk: Token, namespace: ?Namespace, intended_parent: *Node) Element {
    // Ignore the Speculative Parser and start on step 3.
    const document = intended_parent.node_doc;
    const local = tk.local_name;
    var token_attrs: ?std.ArrayList(Attribute) = null;
    const is = switch (tk) {
        .TagToken => |tag| {
            token_attrs = tag.attr;
            tag.getAttrVal("is");
        },
        else => null,
    };
    const registry = lookingUpCustomElementRegistry(intended_parent);
    const definition = lookingUpCustomElementDefinition(registry, namespace, local, is);
    // Whether will execute script.
    const will_exec_script = if (definition != null and !self.fragment_case) blk: {
        break :blk true;
    } else false;

    // Step 9.
    if (will_exec_script) {
        document.*.todmi_counter += 1;
        @panic("[TODO]: This part needs JS runtime");
    }
    const element = self.createElement(document, local, namespace, null, is, will_exec_script, registry);
    if (token_attrs) |ta| element.appendAttrs(ta);

    // Step 12.
    if (will_exec_script) {
        document.*.todmi_counter += 1;
        @panic("[TODO]: ");
    }
    if (!element.isXmlnsXLinkValid()) @panic("[TODO]: Handle parser error.");
    const is_custom = element.isFormAssociatedCustomElement();
    if (element.isResettable() and !is_custom) {
        @panic("[TODO]: Reset algorithm");
    }
    if (element.isFormAssociatedElement() and !is_custom) {
        @panic("[TODO]:");
    }
    return element;
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-an-element-at-the-adjusted-insertion-location
pub fn adjustedInsertionLocation(self: *TreeBuilder, pos: ?*InsertionLocation) InsertionLocation {
    const override_target = if (pos) |p| p.getParent() else null;
    const adjusted_loc = self.appropriatePlaceForInsertion(override_target);

    // Step: 3.
    const node = adjusted_loc.getParent();
    if (node == self.htmlElement()) {
        @panic("[TODO]: need parser.");
    }
    return adjusted_loc;
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-an-element-at-the-adjusted-insertion-location
pub fn insertElementAtAdjustedInsertionLocation(self: *TreeBuilder, el: *Element) void {
    const insertion_loc = self.adjustedInsertionLocation(null);
    // Check if it's possible to insert element at insertion_loc.
    if (!self.isPossibleToInsert()) return;
    if (true) @panic("[TODO] Step 3: need parser.");
    self.insertElementAt(el, insertion_loc);
    if (true) @panic("[TODO] Step 5: need parser.");
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-a-foreign-element
pub fn insertForeignElement(self: *TreeBuilder, tk: Token, namespace: Namespace, only_add_to_element_stack: bool) *Element {
    const adjusted_loc = self.appropriatePlaceForInsertion(null);
    const element = self.createElementForToken(tk, namespace, adjusted_loc.getParent());
    if (!only_add_to_element_stack) self.insertElementAtAdjustedInsertionLocation(element);
    self.open_elements.append(self.allocator, element);
    return element;
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-an-html-element
pub fn insertHtmlElemnt(self: *TreeBuilder, tk: Token) void {
    self.insertForeignElement(tk, .NS_Html, false);
}

pub inline fn currentNode(self: *TreeBuilder) *Element {
    if (self.open_elements.items.len == 0) @panic("Empty open elements stack.");
    return self.open_elements.items[self.open_elements.items.len - 1];
}

pub fn lastStackElement(self: *TreeBuilder, elem: LocalTag) ?Element {
    for (self.open_elements.items..0) |idx| {
        if (self.open_elements.items[idx].local_name.is(elem)) {
            return self.open_elements.items[idx];
        }
    }
    return null;
}

pub inline fn htmlElement(self: *TreeBuilder) ?*Element {
    if (self.open_elements.items.len == 0) return null;
    return self.open_elements.items[0];
}

// https://html.spec.whatwg.org/#look-up-a-custom-element-registry
pub fn lookingUpCustomElementRegistry(intended_parent: *Node) *CustomElementRegistry {
    switch (intended_parent.type_id) {
        .DOM_Element => intended_parent.downcast(.DOM_Element).custom_element_registry,
        .DOM_Document => intended_parent.downcast(.DOM_Document).custom_element_registry,
        .DOM_ShadowRoot => intended_parent.downcast(.DOM_ShadowRoot).custom_element_registry,
        else => null,
    }
}

// https://html.spec.whatwg.org/#look-up-a-custom-element-definition
pub fn lookingUpCustomElementDefinition(registry: ?*CustomElementRegistry, namespace: ?Namespace, local: LocalName, is: ?LocalName) ?CustomElementDefinition {
    if (registry) |reg| {
        if (namespace) |n| {
            if (n != .NS_Html) return null;
            if (reg.lookup(local, local)) |res| return res else if (is) |is_| {
                if (reg.lookup(is_, local)) |res| return res;
            }
        } else return null;
    }
    return null;
}

pub fn createElement(self: *TreeBuilder, document: *Document, local: LocalName, namespace: ?Namespace, prefix: ?[]const u8, is: ?LocalName, sce: bool, registry: ?*CustomElementRegistry) *Element {
    _ = self;
    _ = document;
    _ = local;
    _ = namespace;
    _ = prefix;
    _ = is;
    _ = sce;
    _ = registry;
    @panic("[TODO]: ");
}

// TODO:
pub fn isPossibleToInsert(self: *const TreeBuilder) bool {
    _ = self;
    return true;
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-a-character
pub fn insertCharacter(self: *TreeBuilder, chars: ?[]const u8, tk: Token) void {
    const data = StraleUtf8Global.fromSlice(chars) orelse switch (tk) {
        .CharacterToken => |ct| ct.clone(),
        else => {},
    };

    const insert_loc = self.adjustedInsertionLocation(null);
    const parent = insert_loc.getParent();
    if (parent.type_id == .DOM_Document) return;

    if (insert_loc.beforeNode()) |previous| {
        if (previous.isA(.DOM_Text)) {
            const text = previous.downcast(Text);

            text.data.append(data);
            return;
        }
    }

    const document = parent.asNode().node_doc;
    const text = self.createTextNode(
        document,
        data,
    );
    _ = text;
    @panic("[TODO]: Insert text at insert_loc.");
}

fn insertElementAt(
    self: *TreeBuilder,
    element: *Element,
    location: InsertionLocation,
) void {
    _ = self;
    const node = element.asNode();
    switch (location) {
        .last_child => |parent| {
            parent.asNode().appendChild(node);
        },

        .before_child => |before| {
            const parent = before.node.parent.?.asNode();
            parent.insertBefore(node, before);
        },

        .parent_before_child => |loc| {
            loc.parent.asNode().insertBefore(node, loc.before_child);
        },
    }
}

pub fn createTextNode(self: *TreeBuilder, doc: *Document, data: StraleUtf8Global) Text {
    _ = self;
    _ = doc;
    _ = data;
    @panic("[TODO]:");
}
