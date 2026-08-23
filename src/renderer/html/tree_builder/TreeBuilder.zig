const TreeBuilder = @This();

const std = @import("std");
const token_ = @import("../tokenizer/token.zig");
const Token = token_.Token;
const ProcessingInstruction = token_.ProcessingInstruction;
const Attribute = token_.Attribute;
const Node = @import("../../dom/Node.zig");
const Element = @import("../../dom/Element.zig");
const Text = @import("../../dom/Text.zig");
const Comment = @import("../../dom/Comment.zig");
const Document = @import("../../dom/Document.zig");
const DocumentType = @import("../../dom/DocumentType.zig");
const Attrs = @import("../../dom/Attrs.zig");
const CustomElementRegistry = @import("../../dom/CustomElementRegistry.zig");
const CustomElementDefinition = @import("../../dom/CustomElementDefinition.zig");
const Namespace = @import("../../dom/namespace.zig").Namespace;
const Tokenizer = @import("../tokenizer/Tokenizer.zig");
const TokenizerState = @import("../tokenizer/state.zig").TokenizerState;
const encoding_ = @import("../encoding/encoding.zig");
const Encoding = encoding_.Encoding;
const enc_map = encoding_.enc_map;
const ln = @import("local_name");
const LocalName = ln.LocalName;
const LocalTag = ln.LocalTag;
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;
const ascii = @import("../../utils/ascii.zig");
const types = @import("types.zig");
const ProcessResult = types.ProcessResult;
const ActiveFormatElement = types.ActiveFormatElement;
const InsertionMode = types.InsertionMode;
const InsertionLocation = types.InsertionLocation;
const ScriptingMode = types.ScriptingMode;
const dom_type = @import("../../dom/type.zig");
const OpenElementStack = @import("OpenElementStack.zig");
const TreeAdapter = @import("TreeAdapter.zig");
const TreeBuilderError = @import("error.zig").TreeBuilderError;
const ShadowRootMode = dom_type.ShadowRootMode;
const SlotAssignment = dom_type.SlotAssignment;

allocator: std.mem.Allocator,
adapter: TreeAdapter,
open_elements: OpenElementStack,
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
document: Document,
context: ?*Element,
// Element pointer: https://html.spec.whatwg.org/multipage/parsing.html#the-element-pointers
head_el_ptr: ?*Element,
form_el_ptr: ?*Element,
active_fmt_els: std.ArrayList(ActiveFormatElement),
allow_decl_shadow_roots: bool,
pending_table_char_tks: std.ArrayList(*Token),

pub fn init(alloc: std.mem.Allocator, adapter: TreeAdapter, fragment_case: bool) TreeBuilder {
    return TreeBuilder{
        .allocator = alloc,
        .adapter = adapter,
        .open_elements = OpenElementStack.init(alloc),
        .insert_mode = .InitialMode,
        .orig_insert_mode = .InitialMode,
        .temp_insert_modes = .empty,
        .fragment_case = fragment_case,
        .scripting_mode = .Normal,
        .foster_parenting = false,
        .frameset_ok = true,
        .document = Document.init(),
        .context = null,
        .head_el_ptr = null,
        .form_el_ptr = null,
        .active_fmt_els = .empty,
        .allow_decl_shadow_roots = false,
        .pending_table_char_tks = .empty,
    };
}

pub fn deinit(self: *TreeBuilder) void {
    self.open_elements.deinit();
}

/// Implement TokenIngester.
pub fn handleToken(self: *TreeBuilder, tk: Token) void {
    // If need to acknowledge the token's self-closing flag.
    const need_ack = switch (tk) {
        .TagToken => |tag| tag.kind == .StartTag and tag.self_closing,
        else => false,
    };
    _ = need_ack;

    // Dispatch token.
    const result = if (self.isForeign(tk))
        self.processTokenForeign(tk)
    else
        self.processToken(tk);

    switch (result) {
        else => {},
    }
}

// https://html.spec.whatwg.org/#tree-construction-dispatcher
pub fn isForeign(self: *const TreeBuilder, tk: Token) bool {
    if (self.open_elements.len() == 0 or std.meta.activeTag(tk) == .EofToken) return false;
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

pub fn processToken(self: *const TreeBuilder, tk: Token) ProcessResult {
    return self.step_E(tk);
}

pub fn processTokenForeign(self: *const TreeBuilder, tk: Token) ProcessResult {
    _ = self;
    _ = tk;
    @panic("[TODO]");
}

pub inline fn adjustedCurrentNode(self: *TreeBuilder) *Node {
    if (self.fragment_case and self.open_elements.len() == 1)
        return (self.context orelse @panic("Context no set.")).asNode();

    return self.currentNode();
}

pub inline fn isAdjustedCurrentNodeTopmost(self: *TreeBuilder) bool {
    if (self.fragment_case and self.open_elements.len() == 1)
        return false;

    return true;
}

// https://html.spec.whatwg.org/#appropriate-place-for-inserting-a-node
pub fn appropriatePlaceForInsertion(self: *TreeBuilder, override_target: ?*Element) InsertionLocation {
    const target = override_target orelse self.currentNode();
    if (self.foster_parenting and target.in(&.{ .table, .tbody, .tfoot, .thead, .tr })) {
        const open_elements = self.open_elements;
        var last_table: ?*Element = null;
        var last_table_pos: usize = 0;
        var idx = open_elements.len();
        blk: while (idx > 0) {
            idx -= 1;
            const el = self.open_elements.at(idx);
            if (el.local_name.is(.table)) {
                last_table = el;
                last_table_pos = idx;
                break :blk;
            }
            if (el.local_name.is(.template))
                return .{ .last_child = el.asNode() };
        }

        if (last_table) |table| {
            const table_nd = table.asNode();
            if (table_nd.parent) |p|
                return .{ .parent_before_child = .{
                    .parent = p,
                    .before_child = table_nd,
                } }
            else if (last_table_pos > 0)
                return .{ .last_child = self.open_elements.at(last_table_pos - 1).asNode() }
            else
                @panic("This should never happen: last_table_pos <= 0");
        } else return .{ .last_child = (self.htmlElement() orelse target).asNode() };
    }
    return .{ .last_child = target.asNode() };
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
    const element = Element.create(document, local, namespace, null, is, will_exec_script, registry);
    if (token_attrs) |ta| element.appendAttrs(ta);

    // Step 12.
    if (will_exec_script) {
        document.*.todmi_counter += 1;
        @panic("[TODO]: ");
    }
    if (!element.isXmlnsXLinkValid()) @panic("[TODO]: Handle parser error.");
    const is_custom = element.isFormAssociatedCustomElement();
    if (element.isResettable() and !is_custom)
        @panic("[TODO]: Reset algorithm");

    if (element.isFormAssociatedElement() and !is_custom)
        @panic("[TODO]:");

    return element;
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-an-element-at-the-adjusted-insertion-location
pub fn adjustedInsertionLocation(self: *TreeBuilder, pos: ?*InsertionLocation) InsertionLocation {
    const override_target = if (pos) |p| p.getParent() else null;
    const adjusted_loc = self.appropriatePlaceForInsertion(override_target.downcast(Element));

    // Step: 3.
    const node = adjusted_loc.getParent();
    if (self.htmlElement()) |html|
        if (node == html.asNode()) @panic("[TODO]: need parser.");

    return adjusted_loc;
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-an-element-at-the-adjusted-insertion-location
pub fn insertElementAtAdjustedInsertionLocation(self: *TreeBuilder, el: *Element) void {
    const insertion_loc = self.adjustedInsertionLocation(null);
    // Check if it's possible to insert element at insertion_loc.
    if (!self.isPossibleToInsert()) return;
    const node = insertion_loc.getParent();
    if (node.type_id == .DOM_Document) {
        const document = Document.fromNode(insertion_loc);
        if (document.asNode().hasChild(.DOM_Element)) return;
    }
    Node.ensurePreInsertValidity(el.asNode(), node, null, &.{});
    // TODO: Step 4: Need relevant agent.
    self.insertElementAt(el, insertion_loc);
    // TODO: Step 6: Need relevant agent.
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
pub fn insertHtmlElement(self: *TreeBuilder, tk: Token) *Element {
    return self.insertForeignElement(tk, .NS_Html, false);
}

pub const TextParsingType = enum {
    TPT_Rawtext,
    TPT_Rcdata,
};

// https://html.spec.whatwg.org/multipage/parsing.html#parsing-elements-that-contain-only-text
pub fn parseGenericTextElement(
    self: *TreeBuilder,
    tk: Token,
    tpt: TextParsingType,
) TokenizerState {
    _ = self.insertHtmlElement(tk);
    const state = switch (tpt) {
        .TPT_Rawtext => .RAWTEXT,
        .TPT_Rcdata => .RCDATA,
    };
    self.orig_insert_mode = self.insert_mode;
    self.insert_mode = .TextMode;
    return state;
}

// https://html.spec.whatwg.org/multipage/parsing.html#generate-implied-end-tags
pub inline fn generateImpliedEndTags(self: *TreeBuilder, exclude: ?LocalTag) void {
    self.open_elements.generateImpliedEndTags(exclude);
}

// https://html.spec.whatwg.org/multipage/parsing.html#generate-all-implied-end-tags-thoroughly
pub inline fn generateAllImpliedEndTagsThoroughly(self: *TreeBuilder) void {
    self.open_elements.generateAllImpliedEndTagsThoroughly();
}

pub inline fn currentNode(self: *TreeBuilder) *Element {
    return self.open_elements.currentNode();
}

pub inline fn lastStackElement(self: *TreeBuilder, elem: LocalTag) ?Element {
    return self.open_elements.lastStackElement(elem);
}

pub inline fn htmlElement(self: *TreeBuilder) ?*Element {
    return self.open_elements.htmlElement();
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

    const document = parent.node_doc;
    const text = Text.create(document, data);
    self.insertNodeAt(text.asNode(), insert_loc);
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-a-comment
pub fn insertComment(self: *TreeBuilder, data: StraleUtf8Global, insertion_location: ?InsertionLocation) void {
    const insert_loc = self.adjustedInsertionLocation(insertion_location);
    const parent = insert_loc.getParent();
    const document = parent.node_doc;
    const comment = Comment.create(document, data);
    self.insertNodeAt(comment.asNode(), insert_loc);
}

pub fn insertCommentToDocument(self: *TreeBuilder, data: StraleUtf8Global) void {
    self.insertComment(data, .{ .last_child = self.document.asNode() });
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-a-processing-instruction
pub fn insertProcessingInstruction(self: *TreeBuilder, tk: ProcessingInstruction, insertion_location: ?InsertionLocation) void {
    const target = tk.target;
    const data = tk.data;
    const insert_loc = self.adjustedInsertionLocation(insertion_location);

    const parent = insert_loc.getParent();
    const document = parent.node_doc;
    const pi = ProcessingInstruction.create(document, target, data);
    self.insertNodeAt(pi.asNode(), insert_loc);
}

pub fn insertProcessingInstructionToDocument(self: *TreeBuilder, tk: ProcessingInstruction) void {
    self.insertProcessingInstruction(tk, .{ .last_child = self.document.asNode() });
}

fn insertElementAt(
    self: *TreeBuilder,
    element: *Element,
    location: InsertionLocation,
) void {
    self.insertNodeAt(element.asNode(), location);
}

fn insertNodeAt(
    self: *TreeBuilder,
    node: *Node,
    location: InsertionLocation,
) void {
    _ = self;
    switch (location) {
        .last_child => |parent| {
            parent.appendChild(node);
        },

        .before_child => |before| {
            const parent = before.parent orelse return;
            parent.insertBefore(node, before);
        },

        .parent_before_child => |loc| {
            loc.parent.insertBefore(node, loc.before_child);
        },
    }
}

pub inline fn currentTemplateInsertionMode(self: *TreeBuilder) ?InsertionMode {
    if (self.temp_insert_modes.items.len == 0) return null;
    return self.temp_insert_modes.items[self.temp_insert_modes.items.len - 1];
}

// Append token to document node.
pub fn appendToDocument(self: *TreeBuilder, node: *Node) void {
    self.insertNodeAt(node, .{ .last_child = self.document.asNode() });
}

pub inline fn hasElement(self: *const TreeBuilder, name: LocalTag) bool {
    self.open_elements.hasElement(name);
}

pub inline fn allElementsOneOf(self: *const TreeBuilder, tags: []const LocalTag) bool {
    self.open_elements.allElementsOneOf(tags);
}

pub fn clearActiveFormattingElementsToLastMarker(self: *TreeBuilder) void {
    while (self.active_fmt_els.items.len > 0) {
        const entry = self.active_fmt_els.pop();
        if (entry) |e| switch (e) {
            .AFE_Marker => return,
            else => {},
        };
    }
}

// TODO:
pub fn resetInsertionModeAppropriately(self: *TreeBuilder) void {
    _ = self;
}

pub inline fn popUntilPopped(self: *TreeBuilder, tag: LocalTag) void {
    self.open_elements.popUntilPopped(tag);
}

pub inline fn popUntil(self: *TreeBuilder, tag: LocalTag) void {
    self.open_elements.popUntil(tag);
}

pub inline fn popUntilOneOfPopped(self: *TreeBuilder, tags: []const LocalTag) void {
    self.open_elements.popUntilOneOfPopped(tags);
}

pub inline fn clearStackBack(self: *TreeBuilder, tags: []const LocalTag) void {
    self.open_elements.clearStackBack(tags);
}

pub fn clearStackBackToTableContext(self: *TreeBuilder) void {
    self.open_elements.clearStackBack(&.{ .table, .template, .html });
}

pub fn clearStackBackToTableBodyContext(self: *TreeBuilder) void {
    self.open_elements.clearStackBack(&.{ .tbody, .tfoot, .thead, .template, .html });
}

pub fn clearStackBackToTableRowContext(self: *TreeBuilder) void {
    self.open_elements.clearStackBack(&.{ .tr, .template, .html });
}

pub fn closeCell(self: *TreeBuilder) void {
    self.open_elements.generateImpliedEndTags(null);
    if (!self.currentNode().local_name.oneOf(&.{ .td, .th }))
        if (true) @panic("[TODO]: Handle Parser Error");

    while (self.open_elements.len() > 0) {
        const el = self.open_elements.pop();
        if (el) |e|
            if (e.ns == .NS_Html and e.local_name.oneOf(&.{ .td, .th })) break;
    }
    self.clearActiveFormattingElementsToLastMarker();
    self.insert_mode = .InRowMode;
}

pub inline fn addAttributesToElement(self: *TreeBuilder, el: *Element, attrs: Attrs) void {
    for (attrs.data.items) |attr| {
        const entry = el.attrs.getFromLocalName(attr.local_name.toTag().?);
        if (entry) |e| el.attrs.append(self.allocator, .{
            .ns = null,
            .prefix = null,
            .local_name = e.local_name,
            .value = e.value,
            .element = null,
        });
    }
}

/// https://html.spec.whatwg.org/multipage/parsing.html#has-an-element-in-table-scope
pub inline fn hasElementInTableScope(self: *const TreeBuilder, target_tag: LocalTag) bool {
    return self.open_elements.hasElementInTableScope(target_tag);
}

inline fn hasElementInScopeCustom(
    self: *const TreeBuilder,
    target_tag: LocalTag,
    comptime extra_html_tags: []const LocalTag,
) bool {
    return self.open_elements.hasElementInScopeCustom(target_tag, extra_html_tags);
}

// https://html.spec.whatwg.org/multipage/parsing.html#has-an-element-in-scope
pub inline fn hasElementInScope(self: *const TreeBuilder, target_tag: LocalTag) bool {
    return self.hasElementInScopeCustom(target_tag, &.{});
}

// https://html.spec.whatwg.org/multipage/parsing.html#has-an-element-in-list-item-scope
pub inline fn hasElementInListItemScope(self: *const TreeBuilder, target_tag: LocalTag) bool {
    return self.hasElementInScopeCustom(target_tag, &.{ .ol, .ul });
}

// https://html.spec.whatwg.org/multipage/parsing.html#has-an-element-in-button-scope
pub inline fn hasElementInButtonScope(self: *const TreeBuilder, target_tag: LocalTag) bool {
    return self.hasElementInScopeCustom(target_tag, &.{.button});
}

pub fn parseError(self: *const TreeBuilder, err: TreeBuilderError) void {
    self.adapter.handleError(err);
}

pub fn reconstructActiveFormattingElements(self: *TreeBuilder) void {
    _ = self;
}

pub fn closePElement(self: *TreeBuilder) void {
    _ = self;
}

pub fn handleNewLine(self: *TreeBuilder) void {
    _ = self;
}

pub fn handleListItemStartTag(self: *TreeBuilder, tk: token_.Tag, tag: LocalTag) void {
    _ = self;
    _ = tk;
    _ = tag;
}

pub fn pushActiveFormattingElement(self: *TreeBuilder, el: *Element) void {
    _ = self;
    _ = el;
}

pub fn adoptionAgencyAlgorithm(self: *TreeBuilder, tk: token_.Tag) void {
    _ = self;
    _ = tk;
}

pub fn removeFromStack(self: *TreeBuilder, el: *Element) void {
    _ = self;
    _ = el;
}

pub inline fn unexpect(self: *TreeBuilder, tk: Token, mode: InsertionMode) void {
    self.parseError(.{ .unexpected = .{ .tk = tk, .mode = mode } });
}

/// A `null` mode means the token is processed or reprocessed using the current
/// `self.insert_mode`. A non-null mode temporarily overrides the insertion mode
/// for this call without modifying `self.insert_mode`.
pub fn step_E(self: *TreeBuilder, tk: Token, mode: ?InsertionMode) !ProcessResult {
    switch (mode orelse self.insert_mode) {
        // https://html.spec.whatwg.org/multipage/parsing.html#the-initial-insertion-mode
        .InitialMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    return .PR_Done;
                },
                .CommentToken => |cmt_tk| {
                    self.insertCommentToDocument(cmt_tk);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstructionToDocument(pi_tk);
                    return .PR_Done;
                },
                .DoctypeToken => |doc_tk| {
                    if (!doc_tk.name.eql("html") or !doc_tk.public_id.isEmpty() or (!doc_tk.system_id.isEmpty and !doc_tk.system_id.eql("about:legacy-compat"))) @panic("[TODO]: Handle Parser Error");
                    self.appendToDocument(DocumentType.create(self.document, doc_tk.name, doc_tk.public_id, doc_tk.system_id).asNode());
                    if (!self.document.isIframeSrcdocDocument() and !self.document.parser_cannot_change_the_mod) {
                        if (doc_tk.isQuirksDoctype()) {
                            self.document.mode = .DM_Quirks;
                        } else if (doc_tk.isLimitedQuirksDoctype()) {
                            self.document.mode = .DM_LimitedQuirks;
                        }
                    }
                    self.insert_mode = .BeforeHtmlMode;
                    return .PR_Done;
                },
                else => {},
            }
            // Handle anything else here.
            if (!self.document.isIframeSrcdocDocument()) @panic("[TODO]: Handle parser error");

            if (!self.document.parser_cannot_change_the_mod) {
                self.document.mode = .DM_Quirks;
            }

            self.insert_mode = .BeforeHtmlMode;
            // Reprocess.
            return self.step_E(tk, null);
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#the-before-html-insertion-mode
        .BeforeHtmlMode => {
            sw: switch (tk) {
                .DoctypeToken => {
                    @panic("[TODO]: Handle Parser Error");
                },
                .CommentToken => |cmt_tk| {
                    self.insertCommentToDocument(cmt_tk);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstructionToDocument(pi_tk);
                    return .PR_Done;
                },
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.html)) {
                                const html_elem = self.createElementForToken(tag_tk, .NS_Html, self.document);
                                self.appendToDocument(html_elem.asNode());
                                try self.open_elements.append(html_elem);
                                self.insert_mode = .BeforeHeadMode;
                                return .PR_Done;
                            }
                            break :sw;
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.head) or tag_tk.name.is(.body) or tag_tk.name.is(.html) or tag_tk.name.is(.br)) {
                                break :sw;
                            }
                            @panic("[TODO]: Handle Parser Error");
                        },
                    }
                },
                else => {},
            }

            // Anything else.
            const html_elem = Element.create(self.document, LocalName.fromTag(.html), null, null, null, false, null);
            self.appendToDocument(html_elem.asNode());
            try self.open_elements.append(self.allocator, html_elem);
            self.insert_mode = .BeforeHeadMode;
            return self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#the-before-head-insertion-mode
        .BeforeHeadMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    return .PR_Done;
                },
                .CommentToken => |cmt_tk| {
                    self.insertComment(cmt_tk, null);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstruction(pi_tk, null);
                    return .PR_Done;
                },
                .DoctypeToken => {
                    @panic("[TODO]: Handle Parser Error");
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.html)) {
                                self.step_E(tk, .InBodyMode);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.head)) {
                                const head_elem = self.insertHtmlElement(tag_tk);
                                self.head_el_ptr = head_elem;
                                self.insert_mode = .InHeadMode;
                                return .PR_Done;
                            }
                            break :sw;
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.head) or tag_tk.name.is(.body) or tag_tk.name.is(.html) or tag_tk.name.is(.br)) {
                                break :sw;
                            }
                            @panic("[TODO]: Handle Parser Error");
                        },
                    }
                },
                else => {},
            }

            // Anything else
            const head_elem = self.insertHtmlElement(.{
                .TagToken = .{
                    .kind = .StartTag,
                    .name = LocalName.fromTag(.head),
                    .attrs = .empty,
                    .self_closing = false,
                },
            });
            self.head_el_ptr = head_elem;
            self.insert_mode = .InHeadMode;
            return self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inhead
        .InHeadMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| {
                    // ASCII whitespace -> Insert the character
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    self.insertCharacter(null, ch_tk);
                    return .PR_Done;
                },
                .CommentToken => |cmt_tk| {
                    self.insertComment(cmt_tk, null);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstruction(pi_tk, null);
                    return .PR_Done;
                },
                .DoctypeToken => {
                    @panic("[TODO]: Handle Parser Error");
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.html)) {
                                self.step_E(tk, .InBodyMode);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.base) or tag_tk.name.is(.basefont) or tag_tk.name.is(.bgsound) or tag_tk.name.is(.link)) {
                                _ = self.insertHtmlElement(tag_tk);
                                _ = self.open_elements.pop();
                                return .PR_AckSelfClosing;
                            } else if (tag_tk.name.is(.meta)) {
                                const elem = self.insertHtmlElement(tag_tk);
                                _ = elem;
                                _ = self.open_elements.pop();
                                // TODO: need speculative html parser.
                                //                                if (elem.attrs.getFromLocalName(.charset)) |attr| {
                                //                                    const encoding = enc_map[attr.value.toLowerCase.slice()];
                                //                                } else {
                                //
                                //                                }
                                if (true) @panic("[TODO]: Handle encoding.");
                                return .PR_AckSelfClosing;
                            } else if (tag_tk.name.is(.title)) {
                                const state = self.parseGenericTextElement(tag_tk, .TPT_Rcdata);
                                return .{ .PR_ChangeState = state };
                            } else if ((tag_tk.name.is(.noscript) and self.scripting_mode != .Disabled) or tag_tk.name.is(.noframes) or tag_tk.name.is(.style)) {
                                const state = self.parseGenericTextElement(tag_tk, .TPT_Rawtext);
                                return .{ .PR_ChangeState = state };
                            } else if (tag_tk.name.is(.noscript) and self.scripting_mode == .Disabled) {
                                _ = self.insertHtmlElement(tag_tk);
                                self.insert_mode = .InHeadNoscriptMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.script)) {
                                const adjust_loc = self.appropriatePlaceForInsertion(null);
                                const parent = adjust_loc.getParent();
                                const document = parent.node_doc;
                                const el = self.createElementForToken(tag_tk, .NS_Html, document);
                                if (self.scripting_mode != .Fragment) el.parser_doc = self.document;
                                el.force_async = false;
                                if (self.scripting_mode == .Inert) el.already_started = true;
                                // TODO: Here ignore the step_E 6.
                                self.insertNodeAt(el.asNode(), adjust_loc);
                                try self.open_elements.append(self.allocator, el);
                                self.orig_insert_mode = self.insert_mode;
                                self.insert_mode = .TextMode;
                                return .{ .PR_ChangeState = .ScriptData };
                            } else if (tag_tk.name.is(.template)) {
                                const tmp_tag = tag_tk;
                                try self.active_fmt_els.append(self.allocator, .AFE_Marker);
                                self.frameset_ok = false;
                                self.insert_mode = .InTemplateMode;
                                try self.temp_insert_modes.append(self.allocator, .InTemplateMode);
                                const adjust_loc = self.appropriatePlaceForInsertion(null);
                                const intended_parent = adjust_loc.getParent();
                                self.document = intended_parent.node_doc;
                                if (tmp_tag.shadowRootMode != .SRM_None or !self.allow_decl_shadow_roots or self.isAdjustedCurrentNodeTopmost()) {
                                    self.insertHtmlElement(tag_tk);
                                } else {
                                    const decl_she = self.adjustedCurrentNode();
                                    const temp = self.insertForeignElement(tmp_tag, .NS_Html, true);
                                    const sr_mode = tmp_tag.shadowRootMode();
                                    const slot_ass = .SA_Named;
                                    if (tmp_tag.shadowRootSlotAssignment() == .SA_Manual) slot_ass = .SA_Manual;
                                    const clonable = tmp_tag.hasAttrName("shadowrootclonable");
                                    const serializable = tmp_tag.hasAttrName("shadowrootserializable");
                                    const delegate_focus = tmp_tag.hasAttrName("shadowrootdelegatesfocus");
                                    if (decl_she.shadow_root != null) {
                                        self.insertElementAtAdjustedInsertionLocation(temp);
                                    } else {
                                        const registry = if (tmp_tag.hasAttrName("shadowrootcustomelementregistry")) null else {
                                            decl_she.node_doc.custom_element_registry;
                                        };
                                        decl_she.attachShadowRoot(sr_mode, clonable, serializable, delegate_focus, slot_ass, registry) catch {
                                            self.insertElementAtAdjustedInsertionLocation(temp);
                                            // TODO: Optionally report the error.
                                            return;
                                        };
                                        const shadow = decl_she.shadow_root;
                                        shadow.declarative = true;
                                        temp.temp_contents = shadow;
                                        shadow.available = true;
                                        shadow.keep_cer_null = tmp_tag.hasAttrName("shadowrootcustomelementregistry");
                                    }
                                }
                            } else if (tag_tk.name.is(.head)) {
                                @panic("[TODO]: Handle Parser Error");
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.head)) {
                                _ = self.open_elements.pop();
                                self.insert_mode = .AfterHeadMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.template)) {
                                if (!self.hasElement(.template)) {
                                    if (true) @panic("[TODO]: handle parse error");
                                    return;
                                }
                                self.generateAllImpliedEndTagsThoroughly();
                                if (self.currentNode().local_name.is(.template)) @panic("[TODO]: handle parse error");
                                self.popUntilPopped(.template);
                                self.clearActiveFormattingElementsToLastMarker();
                                _ = self.temp_insert_modes.pop();
                                self.resetInsertionModeAppropriately();
                            } else if (tag_tk.name.is(.body) or tag_tk.name.is(.html) or tag_tk.name.is(.br)) {
                                break :sw;
                            }
                            @panic("[TODO]: Handle Parser Error");
                        },
                    }
                },
                else => break :sw,
            }

            // Anything else
            _ = self.open_elements.pop();
            self.insert_mode = .AfterHeadMode;
            return self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inheadnoscript
        .InHeadNoscriptMode => {
            switch (tk) {
                .DoctypeToken => {
                    if (true) @panic("[TODO]: handle parse error");
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) {
                                return self.step_E(tag_tk, .InBodyMode);
                            }
                            if (tag_tk.name.oneOf(&.{ .basefont, .bgsound, .link, .meta, .noframes })) return self.step_E(tag_tk, .InHeadMode);
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.noscript)) {
                                _ = self.open_elements.pop();
                                self.insert_mode = .InHeadMode;
                                return .PR_Done;
                            }
                            if (!tag_tk.name.is(.br)) {
                                if (true) @panic("[TODO]: handle parse error");
                                return .PR_Done;
                            }
                        },
                    }
                },
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) return self.step_E(ch_tk, .InHeadMode);
                    }
                },
                .CommentToken => |cmt_tk| {
                    return self.step_E(cmt_tk, .InHeadMode);
                },
                .ProcessingInstructionToken => |pi_tk| {
                    return self.step_E(pi_tk, .InHeadMode);
                },
            }

            // Anything else
            if (true) @panic("[TODO]: handle parse error");
            _ = self.open_elements.pop();
            self.insert_mode = .InHeadMode;
            self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#the-after-head-insertion-mode
        .AfterHeadMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    self.insertCharacter(null, ch_tk);
                    return .PR_Done;
                },
                .CommentToken => |cmt_tk| {
                    self.insertComment(cmt_tk, null);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstruction(pi_tk, null);
                    return .PR_Done;
                },
                .DoctypeToken => {
                    if (true) @panic("[TODO]: Handle Parser Error");
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.html)) {
                                return self.step_E(tk, .InBodyMode);
                            } else if (tag_tk.name.is(.body)) {
                                _ = self.insertHtmlElement(tag_tk);
                                self.frameset_ok = false;
                                self.insert_mode = .InBodyMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.frameset)) {
                                _ = self.insertHtmlElement(tag_tk);
                                self.insert_mode = .InFramesetMode;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title })) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                const head_el = self.head_el_ptr.?;
                                try self.open_elements.append(self.allocator, head_el) catch @panic("OOM");
                                const res = self.step_E(tk, .InHeadMode);
                                if (std.mem.indexOfScalar(*Element, self.open_elements.items, head_el)) |idx| {
                                    _ = self.open_elements.orderedRemove(idx);
                                }
                                return res;
                            } else if (tag_tk.name.is(.head)) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                return .PR_Done;
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.template)) {
                                return self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.is(.body) or tag_tk.name.is(.html) or tag_tk.name.is(.br)) {
                                break :sw;
                            }
                            if (true) @panic("[TODO]: Handle Parser Error");
                            return .PR_Done;
                        },
                    }
                },
                else => {},
            }

            // Anything else
            _ = self.insertHtmlElement(.{
                .TagToken = .{
                    .kind = .StartTag,
                    .name = LocalName.fromTag(.body),
                    .attrs = .empty,
                    .self_closing = false,
                },
            });
            self.insert_mode = .InBodyMode;
            return self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inbody
        .InBodyMode => {
            switch (tk) {
                .CharacterToken => |ch_tk| {
                    if (ch_tk.eql("\u{0000}")) {
                        self.unexpect(ch_tk, mode);
                        return .PR_Done;
                    }

                    self.reconstructActiveFormattingElements();
                    self.insertCharacter(null, tk);

                    var is_all_ws = true;
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) {
                            is_all_ws = false;
                            break;
                        }
                    }

                    if (!is_all_ws) self.frameset_ok = false;
                    return .PR_Done;
                },
                .CommentToken => |cmt_tk| {
                    self.insertComment(cmt_tk, null);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstruction(pi_tk, null);
                    return .PR_Done;
                },
                .DoctypeToken => |doc_tk| {
                    self.unexpect(doc_tk, .InBodyMode);
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.html)) {
                                self.unexpect(tag_tk, .InBodyMode);
                                if (self.hasElement(.template)) return .PR_Done;
                                self.addAttributesToElement(self.open_elements.items[0], tag_tk.attrs);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title })) {
                                return self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.is(.body)) {
                                self.unexpect(tag_tk, .InBodyMode);
                                if (self.open_elements.len() == 1 or !self.open_elements.items[1].local_name == .body or self.hasElement(.template)) {
                                    return .PR_Done;
                                }
                                self.frameset_ok = false;
                                self.addAttributesToElement(self.open_elements.items[1], tag_tk.attrs);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.frameset)) {
                                self.unexpect(tag_tk, .InBodyMode);
                                if (self.open_elements.len() == 1 or !self.open_elements.items[1].local_name == .body or !self.frameset_ok) {
                                    return .PR_Done;
                                }
                                if (self.open_elements.len() >= 2) {
                                    const second = self.open_elements.items[1];
                                    if (second.asNode().parent()) |parent| {
                                        parent.removeChild(second.asNode());
                                    }
                                }
                                self.popUntil(.html);
                                self.insertHtmlElement(tag_tk);
                                self.insert_mode = .InFramesetMode;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .address, .article, .aside, .blockquote, .center, .details, .dialog, .dir, .div, .dl, .fieldset, .figcaption, .figure, .footer, .header, .hgroup, .main, .menu, .nav, .ol, .p, .search, .section, .summary, .ul })) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                self.insertHtmlElement(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .h1, .h2, .h3, .h4, .h5, .h6 })) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                const cur_node = self.currentNode();
                                if (cur_node.ns == .NS_Html and cur_node.local_name.oneOf(&.{ .h1, .h2, .h3, .h4, .h5, .h6 })) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    _ = self.open_elements.pop();
                                }
                                self.insertHtmlElement(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .pre, .listing })) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                self.insertHtmlElement(tag_tk);
                                // Handle newline at the start of block
                                self.handleNewLine();
                                self.frameset_ok = false;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.form)) {
                                if (self.form_el_ptr != null and !self.hasElement(.template)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                const element = self.insertHtmlElement(tag_tk);
                                if (!self.hasElement(.template)) self.form_el_ptr = element;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.li)) {
                                self.frameset_ok = false;
                                self.handleListItemStartTag(tag_tk, .li);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .dd, .dt })) {
                                self.frameset_ok = false;
                                self.handleListItemStartTag(tag_tk, tag_tk.name.kind);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.plaintext)) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                self.insertHtmlElement(tag_tk);
                                return .{ .PR_ChangeState = .PLAINTEXT };
                            } else if (tag_tk.name.is(.button)) {
                                if (self.hasElementInScope(.button)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    self.generateImpliedEndTags(null);
                                    self.popUntilPopped(.button);
                                }
                                self.reconstructActiveFormattingElements();
                                self.insertHtmlElement(tag_tk);
                                self.frameset_ok = false;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.a)) {
                                if (true) @panic("[TODO]:");
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .b, .big, .code, .em, .font, .i, .s, .small, .strike, .strong, .tt, .u })) {
                                self.reconstructActiveFormattingElements();
                                const element = self.insertHtmlElement(tag_tk);
                                self.pushActiveFormattingElement(element);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.nobr)) {
                                self.reconstructActiveFormattingElements();
                                if (self.hasElementInScope(.nobr)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    self.adoptionAgencyAlgorithm(tag_tk);
                                    self.reconstructActiveFormattingElements();
                                }
                                const element = self.insertHtmlElement(tag_tk);
                                self.pushActiveFormattingElement(element);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .applet, .marquee, .object })) {
                                self.reconstructActiveFormattingElements();
                                self.insertHtmlElement(tag_tk);
                                self.active_fmt_els.append(self.allocator, .AFE_Marker);
                                self.frameset_ok = false;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.table)) {
                                if (self.document.mode != .DM_Quirks and self.hasElementInButtonScope(.p))
                                    self.closePElement();
                                self.insertHtmlElement(tag_tk);
                                self.frameset_ok = false;
                                self.insert_mode = .InTableMode;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .area, .br, .embed, .img, .keygen, .wbr })) {
                                self.reconstructActiveFormattingElements();
                                self.insertHtmlElement(tag_tk);
                                _ = self.open_elements.pop();
                                self.frameset_ok = false;
                                if (tag_tk.self_closing) return .PR_AckSelfClosing;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.input)) {
                                if (self.fragment_case and self.context.?.local_name.is(.select)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                if (self.hasElementInScope(.select)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    self.popUntilPopped(.select);
                                }
                                self.reconstructActiveFormattingElements();
                                self.insertHtmlElement(tag_tk);
                                _ = self.open_elements.pop();
                                if (tag_tk.self_closing) return .PR_AckSelfClosing;

                                const is_hidden = if (tag_tk.attrs.getFromLocalName(.type)) |attr|
                                    attr.value.eqlIgnoreCase("hidden")
                                else
                                    false;

                                if (!is_hidden) self.frameset_ok = false;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .param, .source, .track })) {
                                self.insertHtmlElement(tag_tk);
                                _ = self.open_elements.pop();
                                if (tag_tk.self_closing) return .PR_AckSelfClosing;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.hr)) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                self.insertHtmlElement(tag_tk);
                                _ = self.open_elements.pop();
                                if (tag_tk.self_closing) return .PR_AckSelfClosing;
                                self.frameset_ok = false;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.image)) {
                                self.unexpect(tag_tk, .InBodyMode);
                                var mut_tk = tk;
                                mut_tk.TagToken.name.kind = .img;
                                return self.step_E(mut_tk, null);
                            } else if (tag_tk.name.is(.textarea)) {
                                if (true) @panic("[TODO]:");
                                return .PR_Done;
                            } else if (tag_tk.name.is(.xmp)) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                self.reconstructActiveFormattingElements();
                                self.frameset_ok = false;
                                self.parseGenericTextElement(tag_tk, .TPT_Rawtext);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.iframe)) {
                                self.frameset_ok = false;
                                self.parseGenericTextElement(tag_tk, .TPT_Rawtext);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.noembed) or (tag_tk.name.is(.noscript) and !self.isScriptingDisabled())) {
                                self.parseGenericTextElement(tag_tk, .TPT_Rawtext);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.select)) {
                                self.reconstructActiveFormattingElements();
                                self.insertHtmlElement(tag_tk);
                                self.frameset_ok = false;
                                if (true) @panic("[TODO]:");
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .option, .optgroup })) {
                                if (self.currentNodeIs(.option)) _ = self.open_elements.pop();
                                self.reconstructActiveFormattingElements();
                                self.insertHtmlElement(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .rb, .rtc, .rp, .rt })) {
                                if (self.hasElementInScope(.ruby)) self.generateImpliedEndTags(null);
                                self.insertHtmlElement(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.math) or tag_tk.name.is(.svg)) {
                                if (true) @panic("[TODO]:");
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .caption, .col, .colgroup, .frame, .head, .tbody, .td, .tfoot, .th, .thead, .tr })) {
                                self.unexpect(tag_tk, .InBodyMode);
                                return .PR_Done;
                            }

                            // Any other start tag
                            self.reconstructActiveFormattingElements();
                            self.insertHtmlElement(tag_tk);
                            return .PR_Done;
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.template)) {
                                return self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.is(.body)) {
                                if (!self.hasElementInScope(.body)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                if (self.allElementsOneOf(&.{ .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc, .tbody, .td, .tfoot, .th, .thead, .tr, .body, .html }))
                                    self.insert_mode = .AfterBodyMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.html)) {
                                if (!self.hasElementInScope(.body)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.insert_mode = .AfterBodyMode;
                                return self.step_E(tk, null);
                            } else if (tag_tk.name.oneOf(&.{ .address, .article, .aside, .blockquote, .button, .center, .details, .dialog, .dir, .div, .dl, .fieldset, .figcaption, .figure, .footer, .header, .hgroup, .listing, .main, .menu, .nav, .ol, .pre, .search, .section, .select, .summary, .ul })) {
                                const tag = tag_tk.name.asTag().?;
                                if (!self.hasElementInScope(tag)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.generateImpliedEndTags(null);
                                if (!self.currentNode().local_name.is(tag))
                                    self.unexpect(tag_tk, .InBodyMode);
                                self.popUntilPopped(tag);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.form)) {
                                if (!self.hasElement(.template)) {
                                    const node = self.form_el_ptr;
                                    self.form_el_ptr = null;
                                    if (node == null or !self.hasElementInScope(node.?)) {
                                        self.unexpect(tag_tk, .InBodyMode);
                                        return .PR_Done;
                                    }
                                    self.generateImpliedEndTags(null);
                                    if (self.currentNode() != node.?)
                                        self.unexpect(tag_tk, .InBodyMode);
                                    self.removeFromStack(node.?);
                                } else {
                                    if (!self.hasElementInScope(.form)) {
                                        self.unexpect(tag_tk, .InBodyMode);
                                        return .PR_Done;
                                    }
                                    self.generateImpliedEndTags(null);
                                    if (!self.currentNode().local_name.is(.form))
                                        self.unexpect(tag_tk, .InBodyMode);
                                    self.popUntilPopped(.form);
                                }
                                return .PR_Done;
                            } else if (tag_tk.name.is(.p)) {
                                if (!self.hasElementInButtonScope(.p)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    self.insertHtmlElement(.{
                                        .TagToken = .{
                                            .kind = .StartTagToken,
                                            .name = LocalName.fromTag(.p),
                                            .attrs = .empty,
                                            .self_closing = false,
                                        },
                                    });
                                }
                                self.closePElement();
                                return .PR_Done;
                            } else if (tag_tk.name.is(.li)) {
                                if (!self.hasElementInListItemScope(.li)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.generateImpliedEndTags(.li);
                                if (!self.currentNode().local_name.is(.li))
                                    self.unexpect(tag_tk, .InBodyMode);
                                self.popUntilPopped(.li);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .dd, .dt })) {
                                const tag = tag_tk.name.asTag().?;
                                if (!self.hasElementInScope(tag)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.generateImpliedEndTags(tag);
                                if (!self.currentNode().local_name.is(tag))
                                    self.unexpect(tag_tk, .InBodyMode);
                                self.popUntilPopped(tag);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .h1, .h2, .h3, .h4, .h5, .h6 })) {
                                if (!self.allElementsOneOf(&.{ .h1, .h2, .h3, .h4, .h5, .h6 })) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.generateImpliedEndTags(null);
                                if (!self.currentNode().local_name.is(tag_tk.name.asTag().?))
                                    self.unexpect(tag_tk, .InBodyMode);
                                self.popUntilOneOfPopped(&.{ .h1, .h2, .h3, .h4, .h5, .h6 });
                                return .PR_Done;
                            }
                            // else if (tag_tk.name.is(.sarcasm)) {
                            // Take a deep breath -> Fallthrough to "any other end tag"
                            //  }
                            else if (tag_tk.name.oneOf(&.{ .a, .b, .big, .code, .em, .font, .i, .nobr, .s, .small, .strike, .strong, .tt, .u })) {
                                self.adoptionAgencyAlgorithm(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .applet, .marquee, .object })) {
                                const tag = tag_tk.name.asTag().?;
                                if (!self.hasElementInScope(tag)) {
                                    self.unexpect(tag_tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.generateImpliedEndTags(null);
                                if (!self.currentNode().local_name.is(tag))
                                    self.unexpect(tag_tk, .InBodyMode);
                                self.popUntilPopped(tag);
                                self.clearActiveFormattingElementsToLastMarker();
                                return .PR_Done;
                            } else if (tag_tk.name.is(.br)) {
                                self.unexpect(tag_tk, .InBodyMode);
                                var mut_tk = tk;
                                mut_tk.TagToken.kind = .StartTagToken;
                                return self.step_E(mut_tk, null);
                            }

                            if (true) @panic("[TODO]:");
                            return .PR_Done;
                        },
                    }
                },
                .EofToken => {
                    if (self.temp_insert_modes.items.len > 0) return self.step_E(tk, .InTemplateMode);

                    if (self.allElementsOneOf(&.{ .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc, .tbody, .td, .tfoot, .th, .thead, .tr, .body, .html })) if (true) @panic("[TODO]: handle parse error");
                    return .PR_StopParsing;
                },
            }
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-incdata
        .TextMode => {
            switch (tk) {
                .CharacterToken => |ch_tk| {
                    self.insertCharacter(null, ch_tk);
                    return .PR_Done;
                },
                .EofToken => {
                    if (true) @panic("[TODO]: Handle Parser Error");
                    const node = self.currentNode();
                    if (node.local_name.is(.script)) {
                        node.already_started = true;
                    }
                    _ = self.open_elements.pop();
                    self.insert_mode = self.orig_insert_mode;
                    return self.step_E(tk, null);
                },
                .TagToken => |tag_tk| {
                    if (tag_tk.kind == .EndTagToken) {
                        if (tag_tk.name.is(.script)) {
                            if (true) @panic("[TODO]: script");
                            return .PR_Done;
                        } else {
                            _ = self.open_elements.pop();
                            self.insert_mode = self.orig_insert_mode;
                            return .PR_Done;
                        }
                    }
                },
                else => {},
            }
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intable
        .InTableMode => {
            sw: switch (tk) {
                .CharacterToken => {
                    if (self.currentNode().local_name.oneOf(&.{ .table, .tbody, .template, .tfoot, .thead, .tr })) {
                        self.pending_table_char_tks = .empty;
                        self.orig_insert_mode = self.insert_mode;
                        self.insert_mode = .InTableTextMode;
                        return self.step_E(tk, null);
                    }
                },
                .CommentToken => |cmt_tk| {
                    self.insertComment(cmt_tk, null);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstruction(pi_tk, null);
                    return .PR_Done;
                },
                .DoctypeToken => {
                    if (true) @panic("[TODO]: Handle Parser Error");
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.caption)) {
                                self.clearStackBackToTableContext();
                                try self.active_fmt_els.append(self.allocator, .AFE_Marker) catch @panic("OOM");
                                _ = self.insertHtmlElement(tag_tk);
                                self.insert_mode = .InCaptionMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.colgroup)) {
                                self.clearStackBackToTableContext();
                                _ = self.insertHtmlElement(tag_tk);
                                self.insert_mode = .InColumnGroupMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.col)) {
                                self.clearStackBackToTableContext();
                                _ = self.insertHtmlElement(.{
                                    .TagToken = .{
                                        .kind = .StartTagToken,
                                        .name = LocalName.fromTag(.colgroup),
                                        .attrs = .empty,
                                        .self_closing = false,
                                    },
                                });
                                self.insert_mode = .InColumnGroupMode;
                                return self.step_E(tk, null);
                            } else if (tag_tk.name.oneOf(&.{ .tbody, .tfoot, .thead })) {
                                self.clearStackBackToTableContext();
                                _ = self.insertHtmlElement(tag_tk);
                                self.insert_mode = .InTableBodyMode;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .td, .th, .tr })) {
                                self.clearStackBackToTableContext();
                                _ = self.insertHtmlElement(.{
                                    .TagToken = .{
                                        .kind = .StartTagToken,
                                        .name = LocalName.fromTag(.tbody),
                                        .attrs = .empty,
                                        .self_closing = false,
                                    },
                                });
                                self.insert_mode = .InTableBodyMode;
                                return self.step_E(tk, null);
                            } else if (tag_tk.name.is(.table)) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                if (!self.hasElementInTableScope(.table)) {
                                    return .PR_Done;
                                } else {
                                    self.popUntilPopped(.table);
                                    self.resetInsertionModeAppropriately();
                                    return self.step_E(tk, null);
                                }
                            } else if (tag_tk.name.oneOf(&.{ .style, .script, .template })) {
                                return self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.is(.input)) {
                                const is_hidden = if (tag_tk.attrs.getFromLocalName(.type)) |attr|
                                    attr.value.eqlIgnoreCase("hidden")
                                else
                                    false;

                                if (!is_hidden) break :sw;

                                if (true) @panic("[TODO]: Handle Parser Error");
                                const elem = self.insertHtmlElement(tag_tk);
                                _ = self.open_elements.pop();
                                if (elem.self_closing) return .PR_AckSelfClosing;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.form)) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                if (self.hasElement(.template) or self.form_el_ptr != null) {
                                    return .PR_Done;
                                } else {
                                    const form_elem = self.insertHtmlElement(tag_tk);
                                    self.form_el_ptr = form_elem;
                                    _ = self.open_elements.pop();
                                    return .PR_Done;
                                }
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.table)) {
                                if (!self.hasElementInTableScope(.table)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.popUntilPopped(.table);
                                    self.resetInsertionModeAppropriately();
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.is(.template)) {
                                return self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.oneOf(&.{ .body, .caption, .col, .colgroup, .html, .tbody, .td, .tfoot, .th, .thead, .tr })) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                return .PR_Done;
                            }
                        },
                    }
                },
                .EofToken => {
                    return self.step_E(tk, .InBodyMode);
                },
            }

            // Anything else
            if (true) @panic("[TODO]: Handle Parser Error");
            self.foster_parenting = true;
            const res = self.step_E(tk, .InBodyMode);
            self.foster_parenting = false;
            return res;
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intabletext
        .InTableTextMode => {
            switch (tk) {
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (c == 0) {
                            if (true) @panic("[TODO]: Handle Parser Error");
                            return .PR_Done;
                        }
                    }
                    try self.pending_table_char_tks.append(self.allocator, tk) catch @panic("OOM");
                    return .PR_Done;
                },
                else => {},
            }

            // Anything else
            var contains_non_whitespace = false;
            for (self.pending_table_char_tks.items) |pending_tk| {
                if (pending_tk == .CharacterToken) {
                    for (pending_tk.CharacterToken.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) {
                            contains_non_whitespace = true;
                            break;
                        }
                    }
                }
                if (contains_non_whitespace) break;
            }

            if (contains_non_whitespace) {
                if (true) @panic("[TODO]: Handle Parser Error");
                for (self.pending_table_char_tks.items) |pending_tk| {
                    // Using the rules given in the `anything else` in the `in table` insertion mode.
                    self.foster_parenting = true;
                    _ = self.step_E(pending_tk, .InBodyMode);
                    self.foster_parenting = false;
                }
            } else {
                for (self.pending_table_char_tks.items) |pending_tk| {
                    if (pending_tk == .CharacterToken) {
                        self.insertCharacter(null, pending_tk.CharacterToken);
                    }
                }
            }

            self.pending_table_char_tks.clearRetainingCapacity();
            self.insert_mode = self.orig_insert_mode;
            return self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-incaption
        .InCaptionMode => {
            switch (tk) {
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.oneOf(&.{ .caption, .col, .colgroup, .tbody, .td, .tfoot, .th, .thead, .tr })) {
                                if (!self.hasElementInTableScope(.caption)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.generateImpliedEndTags(null);
                                    if (!self.currentNode().local_name.is(.caption)) {
                                        if (true) @panic("[TODO]: Handle Parser Error");
                                    }
                                    self.popUntilPopped(.caption);
                                    self.clearActiveFormattingElementsToLastMarker();
                                    self.insert_mode = .InTableMode;
                                    return self.step_E(tk, null);
                                }
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.caption)) {
                                if (!self.hasElementInTableScope(.caption)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.generateImpliedEndTags(null);
                                    if (!self.currentNode().local_name.is(.caption)) {
                                        if (true) @panic("[TODO]: Handle Parser Error");
                                    }
                                    self.popUntilPopped(.caption);
                                    self.clearActiveFormattingElementsToLastMarker();
                                    self.insert_mode = .InTableMode;
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.is(.table)) {
                                if (!self.hasElementInTableScope(.caption)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.generateImpliedEndTags(null);
                                    if (!self.currentNode().local_name.is(.caption)) {
                                        if (true) @panic("[TODO]: Handle Parser Error");
                                    }
                                    self.popUntilPopped(.caption);
                                    self.clearActiveFormattingElementsToLastMarker();
                                    self.insert_mode = .InTableMode;
                                    return self.step_E(tk, null);
                                }
                            } else if (tag_tk.name.oneOf(&.{ .body, .col, .colgroup, .html, .tbody, .td, .tfoot, .th, .thead, .tr })) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                return .PR_Done;
                            }
                        },
                    }
                },
                else => {},
            }

            // Anything else
            return self.step_E(tk, .InBodyMode);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-incolgroup
        .InColumnGroupMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    self.insertCharacter(null, ch_tk);
                    return .PR_Done;
                },
                .CommentToken => |cmt_tk| {
                    self.insertComment(cmt_tk, null);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstruction(pi_tk, null);
                    return .PR_Done;
                },
                .DoctypeToken => {
                    if (true) @panic("[TODO]: Handle Parser Error");
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.html)) {
                                return self.step_E(tk, .InBodyMode);
                            } else if (tag_tk.name.is(.col)) {
                                const col_elem = self.insertHtmlElement(tag_tk);
                                _ = self.open_elements.pop();
                                if (col_elem.self_closing) return .PR_AckSelfClosing;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.template)) {
                                return self.step_E(tk, .InHeadMode);
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.colgroup)) {
                                if (!self.currentNode().local_name.is(.colgroup)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableMode;
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.is(.col)) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                return .PR_Done;
                            } else if (tag_tk.name.is(.template)) {
                                return self.step_E(tk, .InHeadMode);
                            }
                        },
                    }
                },
                .EofToken => {
                    return self.step_E(tk, .InBodyMode);
                },
                else => {},
            }

            // Anything else
            if (!self.currentNode().local_name.is(.colgroup)) {
                if (true) @panic("[TODO]: Handle Parser Error");
                return .PR_Done;
            } else {
                _ = self.open_elements.pop();
                self.insert_mode = .InTableMode;
                return self.step_E(tk, null);
            }
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intbody
        .InTableBodyMode => {
            switch (tk) {
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.tr)) {
                                self.clearStackBackToTableBodyContext();
                                _ = self.insertHtmlElement(tag_tk);
                                self.insert_mode = .InRowMode;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .th, .td })) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                self.clearStackBackToTableBodyContext();
                                _ = self.insertHtmlElement(.{
                                    .TagToken = .{
                                        .kind = .StartTagToken,
                                        .name = LocalName.fromTag(.tr),
                                        .attrs = .empty,
                                        .self_closing = false,
                                    },
                                });
                                self.insert_mode = .InRowMode;
                                return self.step_E(tk, null);
                            } else if (tag_tk.name.oneOf(&.{ .caption, .col, .colgroup, .tbody, .tfoot, .thead })) {
                                if (!self.hasElementInTableScope(.tbody) and
                                    !self.hasElementInTableScope(.thead) and
                                    !self.hasElementInTableScope(.tfoot))
                                {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.clearStackBackToTableBodyContext();
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableMode;
                                    return self.step_E(tk, null);
                                }
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.oneOf(&.{ .tbody, .tfoot, .thead })) {
                                if (!self.hasElementInTableScope(tag_tk.name.toTag().?)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                }
                                self.clearStackBackToTableBodyContext();
                                _ = self.open_elements.pop();
                                self.insert_mode = .InTableMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.table)) {
                                if (!self.hasElementInTableScope(.tbody) and
                                    !self.hasElementInTableScope(.thead) and
                                    !self.hasElementInTableScope(.tfoot))
                                {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.clearStackBackToTableBodyContext();
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableMode;
                                    return self.step_E(tk, null);
                                }
                            } else if (tag_tk.name.oneOf(&.{ .body, .caption, .col, .colgroup, .html, .td, .th, .tr })) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                return .PR_Done;
                            }
                        },
                    }
                },
                else => {},
            }

            // Anything else
            return self.step_E(tk, .InTableMode);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intr
        .InRowMode => {
            switch (tk) {
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.oneOf(&.{ .th, .td })) {
                                self.clearStackBackToTableRowContext();
                                _ = self.insertHtmlElement(tag_tk);
                                self.insert_mode = .InCellMode;
                                try self.active_fmt_els.append(self.allocator, .AFE_Marker) catch @panic("OOM");
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .caption, .col, .colgroup, .tbody, .tfoot, .thead, .tr })) {
                                if (!self.hasElementInTableScope(.tr)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.clearStackBackToTableRowContext();
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableBodyMode;
                                    return self.step_E(tk, null);
                                }
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.tr)) {
                                if (!self.hasElementInTableScope(.tr)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.clearStackBackToTableRowContext();
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableBodyMode;
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.is(.table)) {
                                if (!self.hasElementInTableScope(.tr)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.clearStackBackToTableRowContext();
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableBodyMode;
                                    return self.step_E(tk, null);
                                }
                            } else if (tag_tk.name.oneOf(&.{ .tbody, .tfoot, .thead })) {
                                if (!self.hasElementInTableScope(tag_tk.name.toTag().?)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                }

                                if (!self.hasElementInTableScope(.tr)) {
                                    return .PR_Done;
                                }
                                self.clearStackBackToTableRowContext();
                                _ = self.open_elements.pop();
                                self.insert_mode = .InTableBodyMode;
                                return self.step_E(tk, null);
                            } else if (tag_tk.name.oneOf(&.{ .body, .caption, .col, .colgroup, .html, .td, .th })) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                return .PR_Done;
                            }
                        },
                    }
                },
                else => {},
            }

            // Anything else
            return self.step_E(tk, .InTableMode);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intd
        .InCellMode => {
            switch (tk) {
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.oneOf(&.{ .caption, .col, .colgroup, .tbody, .td, .tfoot, .th, .thead, .tr })) {
                                std.debug.assert(self.hasElementInTableScope(.td) or self.hasElementInTableScope(.th));
                                self.closeCell();
                                return self.step_E(tk, null);
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.oneOf(&.{ .td, .th })) {
                                const target_tag = tag_tk.name.toTag().?;
                                if (!self.hasElementInTableScope(target_tag)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.generateImpliedEndTags(null);
                                    if (!self.currentNode().local_name.is(target_tag)) {
                                        if (true) @panic("[TODO]: Handle Parser Error");
                                    }
                                    self.popUntilPopped(target_tag);
                                    self.clearActiveFormattingElementsToLastMarker();
                                    self.insert_mode = .InRowMode;
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.oneOf(&.{ .body, .caption, .col, .colgroup, .html })) {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .table, .tbody, .tfoot, .thead, .tr })) {
                                if (!self.hasElementInTableScope(tag_tk.name.toTag().?)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                } else {
                                    self.closeCell();
                                    return self.step_E(tk, null);
                                }
                            }
                        },
                    }
                },
                else => {},
            }

            // Anything else
            return self.step_E(tk, .InBodyMode);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intemplate
        .InTemplateMode => {
            switch (tk) {
                .CharacterToken, .CommentToken, .ProcessingInstructionToken, .DoctypeToken => {
                    return self.step_E(tk, .InBodyMode);
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.oneOf(&.{ .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title })) {
                                return self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.oneOf(&.{ .caption, .colgroup, .tbody, .tfoot, .thead })) {
                                _ = self.temp_insert_modes.pop();
                                try self.temp_insert_modes.append(self.allocator, .InTableMode);
                                self.insert_mode = .InTableMode;
                                return self.step_E(tk, null);
                            } else if (tag_tk.name.is(.col)) {
                                _ = self.temp_insert_modes.pop();
                                try self.temp_insert_modes.append(self.allocator, .InColumnGroupMode);
                                self.insert_mode = .InColumnGroupMode;
                                return self.step_E(tk, null);
                            } else if (tag_tk.name.is(.tr)) {
                                _ = self.temp_insert_modes.pop();
                                try self.temp_insert_modes.append(self.allocator, .InTableBodyMode);
                                self.insert_mode = .InTableBodyMode;
                                return self.step_E(tk, null);
                            } else if (tag_tk.name.oneOf(&.{ .td, .th })) {
                                _ = self.temp_insert_modes.pop();
                                try self.temp_insert_modes.append(self.allocator, .InRowMode);
                                self.insert_mode = .InRowMode;
                                return self.step_E(tk, null);
                            } else {
                                _ = self.temp_insert_modes.pop();
                                try self.temp_insert_modes.append(self.allocator, .InBodyMode);
                                self.insert_mode = .InBodyMode;
                                return self.step_E(tk, null);
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.template)) {
                                return self.step_E(tk, .InHeadMode);
                            } else {
                                if (true) @panic("[TODO]: Handle Parser Error");
                                return .PR_Done;
                            }
                        },
                    }
                },
                .EofToken => {
                    if (!self.hasElement(.template)) return .PR_StopParsing;
                    if (true) @panic("[TODO]: Handle Parser Error");
                    self.popUntilPopped(.template);
                    self.clearActiveFormattingElementsToLastMarker();
                    _ = self.temp_insert_modes.pop();
                    self.resetInsertionModeAppropriately();
                    return self.step_E(tk, null);
                },
            }
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-afterbody
        .AfterBodyMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    return self.step_E(tk, .InBodyMode);
                },
                .CommentToken => |cmt_tk| {
                    self.insertComment(cmt_tk, .{ .last_child = self.open_elements.items[0].asNode() });
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstruction(pi_tk, .{ .last_child = self.open_elements.items[0].asNode() });
                    return .PR_Done;
                },
                .DoctypeToken => {
                    if (true) @panic("[TODO]: Handle Parser Error");
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.html)) return self.step_E(tk, .InBodyMode);
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.html)) {
                                if (self.frameset_ok) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                }
                                self.insert_mode = .AfterAfterBodyMode;
                                return .PR_Done;
                            }
                        },
                    }
                },
                .EofToken => return .PR_StopParsing,
            }

            // Anything else
            if (true) @panic("[TODO]: Handle Parser Error");
            self.insert_mode = .InBodyMode;
            return self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inframeset
        .InFramesetMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    return self.step_E(ch_tk, .InBodyMode);
                },

                .CommentToken => |cmt_tk| {
                    self.insertComment(cmt_tk);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstruction(pi_tk);
                    return .PR_Done;
                },
                .DoctypeToken => {
                    if (true) @panic("[TODO]: Handle Parser Error");
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.html)) {
                                return self.step_E(tk, .InBodyMode);
                            } else if (tag_tk.name.is(.frameset)) {
                                _ = self.insertHtmlElement(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.frame)) {
                                _ = self.insertHtmlElement(tag_tk);
                                _ = self.open_elements.pop();
                                return .PR_AckSelfClosing;
                            } else if (tag_tk.name.is(.noframes)) {
                                return self.step_E(tk, .InHeadMode);
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.frameset)) {
                                if (self.currentNode().local_name.is(.html)) {
                                    if (true) @panic("[TODO]: Handle Parser Error");
                                    return .PR_Done;
                                }
                                _ = self.open_elements.pop();
                                if (!self.frameset_ok and !self.currentNode().local_name.is(.frameset)) {
                                    self.insert_mode = .AfterFramesetMode;
                                }
                                return .PR_Done;
                            }
                        },
                    }
                },
                .EofToken => {
                    if (!self.currentNode().local_name.is(.html)) {
                        if (true) @panic("[TODO]: Handle Parser Error");
                    }
                    return .PR_StopParsing;
                },
            }

            // Anything else
            if (true) @panic("[TODO]: Handle Parser Error");
            return .PR_Done;
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-afterframeset
        .AfterFramesetMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    self.insertCharacter(null, tk);
                    return .PR_Done;
                },
                .CommentToken => |cmt_tk| {
                    self.insertComment(cmt_tk, null);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstruction(pi_tk, null);
                    return .PR_Done;
                },
                .DoctypeToken => {
                    if (true) @panic("[TODO]: Handle Parser Error");
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTagToken => {
                            if (tag_tk.name.is(.html)) {
                                return self.step_E(tk, .InBodyMode);
                            } else if (tag_tk.name.is(.noframes)) {
                                return self.step_E(tk, .InHeadMode);
                            }
                        },
                        .EndTagToken => {
                            if (tag_tk.name.is(.html)) {
                                self.insert_mode = .AfterAfterFramesetMode;
                                return .PR_Done;
                            }
                        },
                    }
                },
                .EofToken => {
                    return .PR_StopParsing;
                },
                else => {},
            }

            // Anything else
            if (true) @panic("[TODO]: Handle Parser Error");
            return .PR_Done;
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#the-after-after-body-insertion-mode
        .AfterAfterBodyMode => {
            sw: switch (tk) {
                .CommentToken => |cmt_tk| {
                    self.insertCommentToDocument(cmt_tk);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstructionToDocument(pi_tk);
                    return .PR_Done;
                },
                .DoctypeToken => {
                    return self.step_E(tk, .InBodyMode);
                },
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    return self.step_E(tk, .InBodyMode);
                },
                .TagToken => |tag_tk| {
                    if (tag_tk.kind == .StartTagToken and tag_tk.name.is(.html)) {
                        return self.step_E(tk, .InBodyMode);
                    }
                },
                .EofToken => {
                    return .PR_StopParsing;
                },
                else => {},
            }

            // Anything else
            if (true) @panic("[TODO]: Handle Parser Error");
            self.insert_mode = .InBodyMode;
            return self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#the-after-after-frameset-insertion-mode
        .AfterAfterFramesetMode => {
            sw: switch (tk) {
                .CommentToken => |cmt_tk| {
                    self.insertCommentToDocument(cmt_tk);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstructionToDocument(pi_tk);
                    return .PR_Done;
                },
                .DoctypeToken => {
                    return self.step_E(tk, .InBodyMode);
                },
                .CharacterToken => |ch_tk| {
                    for (ch_tk.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(c)) break :sw;
                    }
                    return self.step_E(tk, .InBodyMode);
                },
                .TagToken => |tag_tk| {
                    if (tag_tk.kind == .StartTagToken) {
                        if (tag_tk.name.is(.html)) {
                            return self.step_E(tk, .InBodyMode);
                        } else if (tag_tk.name.is(.noframes)) {
                            return self.step_E(tk, .InHeadMode);
                        }
                    }
                },
                .EofToken => return .PR_StopParsing,
                else => {},
            }

            // Anything else
            if (true) @panic("[TODO]: Handle Parser Error");
            return .PR_Done;
        },
    }
}
