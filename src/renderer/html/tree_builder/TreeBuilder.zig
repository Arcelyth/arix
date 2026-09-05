const TreeBuilder = @This();

const std = @import("std");
const token_ = @import("../tokenizer/token.zig");
const Token = token_.Token;
const Attribute = token_.Attribute;
const Node = @import("../../dom/Node.zig");
const Element = @import("../../dom/Element.zig");
const Text = @import("../../dom/Text.zig");
const Comment = @import("../../dom/Comment.zig");
const Document = @import("../../dom/Document.zig");
const DocumentType = @import("../../dom/DocumentType.zig");
const DocumentFragment = @import("../../dom/DocumentFragment.zig");
const Attrs = @import("../../dom/Attrs.zig");
const CustomElementRegistry = @import("../../dom/CustomElementRegistry.zig");
const CustomElementDefinition = @import("../../dom/CustomElementDefinition.zig");
const ProcessingInstruction = @import("../../dom/ProcessingInstruction.zig");
const Namespace = @import("../../dom/namespace.zig").Namespace;
const Tokenizer = @import("../tokenizer/Tokenizer.zig");
const TokenAdapter = @import("../tokenizer/TokenAdapter.zig");
const Vtable = @import("../tokenizer/TokenAdapter.zig").VTable;
const TokenizerError = @import("../tokenizer/error.zig").TokenizerError;
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
const PendingToken = types.PendingToken;
const dom_type = @import("../../dom/type.zig");
const OpenElementStack = @import("OpenElementStack.zig");
const ActiveFormatElementList = @import("ActiveFormatElementList.zig");
const TreeAdapter = @import("TreeAdapter.zig");
const TreeBuilderError = @import("error.zig").TreeBuilderError;
const ShadowRootMode = @import("../../dom/ShadowRoot.zig").ShadowRootMode;
const SlotAssignment = @import("../../dom/ShadowRoot.zig").ShadowRootSlotAssignment;
const config = @import("config");

allocator: std.mem.Allocator,
tree_adapter: TreeAdapter,
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
document: *Document,
context: ?*Element,
// Element pointer: https://html.spec.whatwg.org/multipage/parsing.html#the-element-pointers
head_el_ptr: ?*Element,
form_el_ptr: ?*Element,
// List of active formatting elements.
active_fmt_els: ActiveFormatElementList,
allow_decl_shadow_roots: bool,
pending_table_char_tks: std.ArrayList(PendingToken),
root_insertion_target: ?*DocumentFragment,
// Fake start tag to make the tree construction algorithm treat the fragment context as a normal HTML start tag.
context_start_tag: ?Token,
// Set after inserting pre, listing, or textarea. The tree builder ignores a
// single leading LF in the next character token.
ignore_next_lf: bool,

pub const TreeBuilderOpts = struct {
    fragment_case: bool = false,
    allow_decl_shadow_roots: bool = false,
    scripting_mode: ScriptingMode = .Normal,
};

pub fn init(alloc: std.mem.Allocator, tree_adapter: TreeAdapter, opts: TreeBuilderOpts) TreeBuilder {
    return TreeBuilder{
        .allocator = alloc,
        .tree_adapter = tree_adapter,
        .open_elements = OpenElementStack.init(alloc),
        .insert_mode = .InitialMode,
        .orig_insert_mode = .InitialMode,
        .temp_insert_modes = .empty,
        .fragment_case = opts.fragment_case,
        .scripting_mode = opts.scripting_mode,
        .foster_parenting = false,
        .frameset_ok = true,
        .document = Document.init(alloc),
        .context = null,
        .head_el_ptr = null,
        .form_el_ptr = null,
        .active_fmt_els = ActiveFormatElementList.init(alloc),
        .allow_decl_shadow_roots = opts.allow_decl_shadow_roots,
        .pending_table_char_tks = .empty,
        .root_insertion_target = null,
        .context_start_tag = null,
        .ignore_next_lf = false,
    };
}

pub fn deinit(self: *TreeBuilder) void {
    self.open_elements.deinit();
    self.temp_insert_modes.deinit(self.allocator);
    self.active_fmt_els.deinit();
    for (self.pending_table_char_tks.items) |*tk| tk.deinit(self.allocator);
    self.pending_table_char_tks.deinit(self.allocator);
    if (self.context_start_tag) |*context_start_tag| context_start_tag.deinit(self.allocator);
    self.document.destroy(self.allocator);
}

// --- Implement TokenAdapter. ---
const vtable = Vtable{
    .handleTokenFn = handleToken,
    .handleErrorFn = handleError,
    .adjustCurrentNodeAndNotInHtmlNamespace = adjustCurrentNodeAndNotInHtmlNamespace,
};

pub fn handleToken(ptr: *anyopaque, token: Token) ?TokenizerState {
    const self: *TreeBuilder = @ptrCast(@alignCast(ptr));
    return self.handlePendingToken(PendingToken.init(token));
}

pub fn handlePendingToken(self: *TreeBuilder, token: PendingToken) ?TokenizerState {
    var tk = token;
    var pending_tokens: std.ArrayList(PendingToken) = .empty;
    defer {
        tk.deinit(self.allocator);
        for (pending_tokens.items) |*pending| pending.deinit(self.allocator);
        pending_tokens.deinit(self.allocator);
    }

    while (true) {
        if (self.ignore_next_lf) {
            self.ignore_next_lf = false;
            if (tk == .CharacterToken) {
                const chars = tk.CharacterToken.slice();
                if (chars.len > 0 and chars[0] == '\n') {
                    if (chars.len == 1) {
                        if (pending_tokens.items.len == 0) return null;
                        tk.deinit(self.allocator);
                        tk = pending_tokens.orderedRemove(0);
                        continue;
                    }
                    const remainder = initPendingCharacter(
                        tk.CharacterToken.split_status,
                        chars[1..],
                    );
                    tk.deinit(self.allocator);
                    tk = remainder;
                }
            }
        }

        const result = if (self.isForeign(tk)) self.processTokenForeign(tk) else self.processToken(tk);

        switch (result) {
            .PR_SplitWhitespace => {
                const chars = tk.CharacterToken.slice();
                if (chars.len == 0) return null;
                const is_whitespace = ascii.isAsciiWhitespace(u8, chars[0]);
                var split_at: usize = 1;
                while (split_at < chars.len and ascii.isAsciiWhitespace(u8, chars[split_at]) == is_whitespace) : (split_at += 1) {}

                var remainder: ?PendingToken = null;
                if (split_at < chars.len) {
                    remainder = .{ .CharacterToken = .{
                        .split_status = .NotSplit,
                        .data = StraleUtf8Global.initSlice(chars[split_at..]) catch @panic("OutOfMemory"),
                    } };
                }
                const first = StraleUtf8Global.initSlice(chars[0..split_at]) catch @panic("OutOfMemory");
                tk.deinit(self.allocator);
                tk = .{ .CharacterToken = .{
                    .split_status = if (is_whitespace) .Whitespace else .NotWhitespace,
                    .data = first,
                } };
                if (remainder) |pending| pending_tokens.append(self.allocator, pending) catch @panic("OutOfMemory");
            },
            .PR_ChangeState => |state| return state,
            .PR_Done, .PR_AckSelfClosing, .PR_StopParsing => {
                if (pending_tokens.items.len == 0) return null;
                tk.deinit(self.allocator);
                tk = pending_tokens.orderedRemove(0);
            },
        }
    }
}

fn initPendingCharacter(status: types.SplitStatus, chars: []const u8) PendingToken {
    return .{ .CharacterToken = .{
        .split_status = status,
        .data = StraleUtf8Global.initSlice(chars) catch @panic("OutOfMemory"),
    } };
}

pub fn handleError(ptr: *anyopaque, err: TokenizerError, cur_line: usize) void {
    _ = ptr;
    _ = err;
    _ = cur_line;
}

pub fn adjustCurrentNodeAndNotInHtmlNamespace(ptr: *anyopaque) bool {
    const self: *TreeBuilder = @ptrCast(@alignCast(ptr));
    return self.open_elements.len() != 0 and self.adjustedCurrentNode().ns != .NS_Html;
}

pub fn adapter(self: *TreeBuilder) TokenAdapter {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}
// --- ---

pub fn tokenizerStateForContextElement(self: *const TreeBuilder, scripting_mode: ScriptingMode) TokenizerState {
    const context = self.context orelse @panic("Miss context element.");
    if (context.ns != .NS_Html) return .Data;
    if (context.local_name.oneOf(&.{ .title, .textarea })) return .RCDATA;
    if (context.local_name.oneOf(&.{ .style, .xmp, .iframe, .noembed, .noframes }) or
        (scripting_mode != .Disabled and context.local_name.is(.noscript))) return .RAWTEXT;
    if (context.local_name.is(.script)) return .ScriptData;
    if (context.local_name.is(.plaintext)) return .PLAINTEXT;
    return .Data;
}

pub inline fn setDocumentType(self: *TreeBuilder, ty: Document.DocType) void {
    self.document.ty = ty;
}

// https://html.spec.whatwg.org/#tree-construction-dispatcher
pub fn isForeign(self: *TreeBuilder, tk: PendingToken) bool {
    if (self.open_elements.len() == 0 or std.meta.activeTag(tk) == .EofToken) return false;
    const cur_el = self.adjustedCurrentNode();

    if (cur_el.ns == .NS_Html) return false;

    if (cur_el.isMathMLTextIntegrationPoint()) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag and !tag.name.is(.mglyph) and !tag.name.is(.malignmark)) return false;
            },
            .CharacterToken => return false,
            else => {},
        }
    }

    if (cur_el.isMathMLAnnotationXml()) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag and tag.name.is(.svg)) return false;
            },
            else => {},
        }
    }

    if (cur_el.isHtmlIntegrationPoint(tk.token())) {
        switch (tk) {
            .TagToken => |tag| {
                if (tag.kind == .StartTag) return false;
            },
            .CharacterToken => return false,
            else => {},
        }
    }

    return true;
}

pub fn processToken(self: *TreeBuilder, tk: PendingToken) ProcessResult {
    return self.step_E(tk, null) catch @panic("[TODO]: handle error.");
}

// https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inforeign
pub fn processTokenForeign(self: *TreeBuilder, tk: PendingToken) ProcessResult {
    return switch (tk) {
        .CharacterToken => |ch_tk| blk: {
            const data = ch_tk.slice();
            var start: usize = 0;
            for (data, 0..) |ch, i| {
                if (ch == 0) {
                    if (start < i) self.insertCharacter_E(data[start..i], tk) catch @panic("out of memory");
                    self.parseError(.null_character);
                    self.insertCharacter_E("\u{FFFD}", tk) catch @panic("out of memory");
                    start = i + 1;
                } else if (!ascii.isAsciiWhitespace(u8, ch)) {
                    self.frameset_ok = false;
                }
            }
            if (start < data.len) self.insertCharacter_E(data[start..], tk) catch @panic("out of memory");
            break :blk .PR_Done;
        },
        .CommentToken => |data| blk: {
            self.insertComment(data, null);
            break :blk .PR_Done;
        },
        .ProcessingInstructionToken => |pi| blk: {
            self.insertProcessingInstruction(pi, null);
            break :blk .PR_Done;
        },
        .DoctypeToken => blk: {
            self.unexpect(tk, self.insert_mode);
            break :blk .PR_Done;
        },
        .TagToken => |tag_value| blk: {
            if (tag_value.isForeignContentBreakout()) {
                self.unexpect(tk, self.insert_mode);
                while (!self.currentNode().isForeignIntegrationBoundary(tk.token()))
                    _ = self.open_elements.pop();
                break :blk self.processToken(tk);
            }

            var tag = tag_value;
            if (tag.kind == .StartTag) {
                const adjusted_current = self.adjustedCurrentNode();
                if (adjusted_current.ns == .NS_Math) tag.adjustMathMLAttributes();
                if (adjusted_current.ns == .NS_Svg) {
                    tag.adjustSVGTagName();
                    tag.adjustSVGAttributes();
                }
                tag.adjustForeignAttributes();

                const ns = adjusted_current.ns orelse .NS_Html;
                _ = self.insertForeignElement_E(tag, ns, false) catch @panic("out of memory");
                if (tag.self_closing) {
                    _ = self.open_elements.pop();
                    break :blk .PR_AckSelfClosing;
                }
            } else {
                var i = self.open_elements.len() - 1;
                if (!std.ascii.eqlIgnoreCase(self.open_elements.at(i).local_name.slice(), tag.name.slice()))
                    self.unexpect(tk, self.insert_mode);

                while (i > 0) {
                    const node = self.open_elements.at(i);
                    if (std.ascii.eqlIgnoreCase(node.local_name.slice(), tag.name.slice())) {
                        while (self.open_elements.len() > i) _ = self.open_elements.pop();
                        break :blk .PR_Done;
                    }
                    i -= 1;
                    if (self.open_elements.at(i).ns == .NS_Html)
                        break :blk self.processToken(tk);
                }
            }
            break :blk .PR_Done;
        },
        .EofToken => self.processToken(tk),
        else => .PR_Done,
    };
}

pub inline fn adjustedCurrentNode(self: *TreeBuilder) *Element {
    if (self.fragment_case and self.open_elements.len() == 1)
        return (self.context orelse @panic("Context no set."));

    return self.currentNode();
}

pub inline fn isAdjustedCurrentNodeTopmost(self: *TreeBuilder) bool {
    if (self.fragment_case and self.open_elements.len() == 1)
        return false;

    return self.open_elements.len() == 1;
}

// https://html.spec.whatwg.org/#appropriate-place-for-inserting-a-node
pub fn appropriatePlaceForInsertion(self: *TreeBuilder, override_target: ?*Node) InsertionLocation {
    const target = override_target orelse self.currentNode().asNode();
    const target_element = if (target.type_id == .DOM_Element) target.downcast(Element) else null;
    if (self.foster_parenting and target_element != null and target_element.?.in(&.{ .table, .tbody, .tfoot, .thead, .tr })) {
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
            if (el.local_name.is(.template)) {
                return .{ .last_child = if (el.temp_contents) |contents|
                    &contents.node
                else
                    el.asNode() };
            }
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
        } else return .{ .last_child = if (self.htmlElement()) |html| html.asNode() else target };
    }
    // FIXME: Move to other suitable place.
    if (target_element) |element| {
        if (element.ns == .NS_Html and element.local_name.is(.template)) {
            if (element.temp_contents) |contents| return .{ .last_child = &contents.node };
        }
    }
    return .{ .last_child = target };
}

// https://html.spec.whatwg.org/#create-an-element-for-the-token
pub fn createElementForToken_E(self: *TreeBuilder, tag: token_.Tag, namespace: ?Namespace, intended_parent: *Node) !*Element {
    // Ignore the Speculative Parser and start on step 3.
    const document = intended_parent.node_doc;
    const local = tag.name.clone();
    const token_attrs: std.ArrayList(Attribute) = tag.attrs;
    const is = if (tag.getAttrVal("is")) |v| v.slice() else null;
    const registry = Element.lookingUpCustomElementRegistry(intended_parent);
    const definition = Element.lookingUpCustomElementDefinition(registry, namespace, local, is);
    // Whether will execute script.
    const will_exec_script = if (definition != null and !self.fragment_case) blk: {
        break :blk true;
    } else false;

    // Step 9.
    if (will_exec_script) {
        document.*.todmi_counter += 1;
        @panic("[TODO]: This part needs JS runtime");
    }
    var element = Element.create(document, local, namespace, null, is, will_exec_script, registry);
    try element.appendAttrs(token_attrs.items);

    // FIXME: Move this logic to other place.
    if (namespace == .NS_Html and element.local_name.is(.template)) {
        const contents = try self.allocator.create(DocumentFragment);
        contents.* = DocumentFragment.init(document);
        element.temp_contents = contents;
        element.temp_contents_owned = true;
    }
    // Step 12.
    if (will_exec_script) {
        document.*.todmi_counter += 1;
        @panic("[TODO]: ");
    }
    if (!element.isXmlnsXLinkValid()) self.parseError(.xml_xlink_not_valid);
    const is_custom = element.isFormAssociatedCustomElement();
    if (element.isResettable() and !is_custom) {
        // TODO;
    }

    if (element.isFormAssociatedElement() and !is_custom) {
        // TODO;
    }

    return element;
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-an-element-at-the-adjusted-insertion-location
pub fn adjustedInsertionLocation(self: *TreeBuilder, pos: ?*const InsertionLocation) InsertionLocation {
    const override_target = if (pos) |p| p.getParent() else null;
    var adjusted_loc = self.appropriatePlaceForInsertion(override_target);

    if (self.root_insertion_target) |root_target| {
        if (adjusted_loc.getParent() == self.open_elements.at(0).asNode())
            adjusted_loc = .{ .last_child = &root_target.node };
    }

    return adjusted_loc;
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-an-element-at-the-adjusted-insertion-location
pub fn insertElementAtAdjustedInsertionLocation(self: *TreeBuilder, el: *Element) void {
    var insertion_loc = self.adjustedInsertionLocation(null);
    // Check if it's possible to insert element at insertion_loc.
    if (!self.isPossibleToInsert()) return;
    const node = insertion_loc.getParent();
    if (node.type_id == .DOM_Document) {
        const document = Document.fromNode(node);
        if (document.asNode().hasChild(.DOM_Element)) return;
    }
    Node.ensurePreInsertValidity(el.asNode(), node, null, &.{});
    // TODO: Step 4: Need relevant agent.
    self.insertElementAt(el, insertion_loc);
    // TODO: Step 6: Need relevant agent.
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-a-foreign-element
pub fn insertForeignElement_E(self: *TreeBuilder, tk: token_.Tag, namespace: Namespace, only_add_to_element_stack: bool) !*Element {
    const adjusted_loc = self.appropriatePlaceForInsertion(null);
    const element = try self.createElementForToken_E(tk, namespace, adjusted_loc.getParent());
    if (!only_add_to_element_stack) self.insertElementAtAdjustedInsertionLocation(element);
    try self.open_elements.append(element);
    return element;
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-an-html-element
pub fn insertHtmlElement_E(self: *TreeBuilder, tk: token_.Tag) !*Element {
    return try self.insertForeignElement_E(tk, .NS_Html, false);
}

pub const TextParsingType = enum {
    TPT_Rawtext,
    TPT_Rcdata,
};

// https://html.spec.whatwg.org/multipage/parsing.html#parsing-elements-that-contain-only-text
pub fn parseGenericTextElement_E(
    self: *TreeBuilder,
    tag: token_.Tag,
    comptime tpt: TextParsingType,
) !TokenizerState {
    _ = try self.insertHtmlElement_E(tag);
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

// TODO:
pub fn isPossibleToInsert(self: *const TreeBuilder) bool {
    _ = self;
    return true;
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-a-character
pub fn insertCharacter_E(self: *TreeBuilder, chars: ?[]const u8, tk: PendingToken) !void {
    const data = if (chars) |slice|
        try StraleUtf8Global.initSlice(slice)
    else switch (tk) {
        .CharacterToken => |ct| ct.data.clone(),
        else => return,
    };

    const insert_loc = self.adjustedInsertionLocation(null);
    const parent = insert_loc.getParent();
    if (parent.type_id == .DOM_Document) return;

    if (insert_loc.beforeNode()) |previous| {
        if (previous.isA(.DOM_Text)) {
            const text = previous.downcast(Text);

            try text.data.append(data.slice());
            return;
        }
    }

    const document = parent.node_doc;
    var text = Text.create(document, data);
    self.insertNodeAt(text.asNode(), insert_loc);
}

fn processCharacterTokenIgnoringNull_E(
    self: *TreeBuilder,
    tk: PendingToken,
    comptime process_run: fn (*TreeBuilder, []const u8, PendingToken, bool) anyerror!void,
) !void {
    const chars = tk.CharacterToken.slice();
    const first_null = std.mem.indexOfScalar(u8, chars, 0) orelse {
        try process_run(self, chars, tk, true);
        return;
    };

    var start: usize = 0;
    var null_at: ?usize = first_null;
    while (null_at) |i| {
        try process_run(self, chars[start..i], tk, false);
        self.parseError(.null_character);
        start = i + 1;
        null_at = std.mem.indexOfScalarPos(u8, chars, start, 0);
    }
    try process_run(self, chars[start..], tk, false);
}

fn processInBodyCharacterRun_E(self: *TreeBuilder, chars: []const u8, tk: PendingToken, whole_token: bool) anyerror!void {
    _ = whole_token;
    if (chars.len == 0) return;
    self.reconstructActiveFormattingElements();
    try self.insertCharacter_E(chars, tk);
    for (chars) |c| {
        if (!ascii.isAsciiWhitespace(u8, c)) {
            self.frameset_ok = false;
            break;
        }
    }
}

fn bufferTableCharacterRun_E(self: *TreeBuilder, chars: []const u8, tk: PendingToken, whole_token: bool) anyerror!void {
    if (chars.len == 0) return;
    try self.pending_table_char_tks.append(self.allocator, .{ .CharacterToken = .{
        .split_status = tk.CharacterToken.split_status,
        .data = if (whole_token) tk.CharacterToken.data.clone() else try StraleUtf8Global.initSlice(chars),
    } });
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-a-comment
pub fn insertComment(self: *TreeBuilder, data: StraleUtf8Global, insertion_location: ?*const InsertionLocation) void {
    const insert_loc = self.adjustedInsertionLocation(insertion_location);
    const parent = insert_loc.getParent();
    const document = parent.node_doc;
    var comment = Comment.create(document, data.clone());
    self.insertNodeAt(comment.asNode(), insert_loc);
}

pub fn insertCommentToDocument(self: *TreeBuilder, data: StraleUtf8Global) void {
    self.insertComment(data, &.{ .last_child = self.document.asNode() });
}

// https://html.spec.whatwg.org/multipage/parsing.html#insert-a-processing-instruction
pub fn insertProcessingInstruction(self: *TreeBuilder, tk: token_.ProcessingInstruction, insertion_location: ?*const InsertionLocation) void {
    const target = tk.target.clone();
    const data = tk.data.clone();
    const insert_loc = self.adjustedInsertionLocation(insertion_location);

    const parent = insert_loc.getParent();
    const document = parent.node_doc;
    var pi = ProcessingInstruction.create(document, target, data);
    self.insertNodeAt(pi.asNode(), insert_loc);
}

pub fn insertProcessingInstructionToDocument(self: *TreeBuilder, tk: token_.ProcessingInstruction) void {
    self.insertProcessingInstruction(tk, &.{ .last_child = self.document.asNode() });
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
    return self.open_elements.hasElement(name);
}

pub inline fn allElementsOneOf(self: *const TreeBuilder, tags: []const LocalTag) bool {
    return self.open_elements.allElementsOneOf(tags);
}

pub fn clearActiveFormattingElementsToLastMarker(self: *TreeBuilder) void {
    while (self.active_fmt_els.len() > 0) {
        const entry = self.active_fmt_els.pop();
        if (entry) |e| switch (e) {
            .AFE_Marker => return,
            else => {},
        };
    }
}

pub fn resetInsertionModeAppropriately(self: *TreeBuilder) void {
    var i = self.open_elements.len();

    while (i > 0) {
        i -= 1;

        const last = self.fragment_case and i == 0;
        const node = if (last)
            self.context orelse self.open_elements.at(i)
        else
            self.open_elements.at(i);

        // Only HTML elements participate in these tag-name checks.
        if (node.ns != .NS_Html) continue;
        const tag = node.local_name.toTag() orelse continue;
        switch (tag) {
            .td, .th => {
                if (last) continue;
                self.insert_mode = .InCellMode;
                return;
            },

            .tr => {
                self.insert_mode = .InRowMode;
                return;
            },

            .tbody, .thead, .tfoot => {
                self.insert_mode = .InTableBodyMode;
                return;
            },

            .caption => {
                self.insert_mode = .InCaptionMode;
                return;
            },

            .colgroup => {
                self.insert_mode = .InColumnGroupMode;
                return;
            },

            .table => {
                self.insert_mode = .InTableMode;
                return;
            },

            .template => {
                self.insert_mode = self.currentTemplateInsertionMode() orelse .InTemplateMode;
                return;
            },

            .head => {
                if (last) continue;
                self.insert_mode = .InHeadMode;
                return;
            },

            .body => {
                self.insert_mode = .InBodyMode;
                return;
            },

            .frameset => {
                self.insert_mode = .InFramesetMode;
                return;
            },

            .html => {
                self.insert_mode = if (self.head_el_ptr == null)
                    .BeforeHeadMode
                else
                    .AfterHeadMode;
                return;
            },

            else => {},
        }
    }

    self.insert_mode = .InBodyMode;
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
        if (true) self.parseError(.close_cell_without_cell);

    while (self.open_elements.len() > 0) {
        const el = self.open_elements.pop();
        if (el) |e|
            if (e.ns == .NS_Html and e.local_name.oneOf(&.{ .td, .th })) break;
    }
    self.clearActiveFormattingElementsToLastMarker();
    self.insert_mode = .InRowMode;
}

pub inline fn addAttributesToElement_E(self: *TreeBuilder, el: *Element, attrs: []Attribute) !void {
    _ = self;
    for (attrs) |attr| {
        var already_present = false;
        for (el.attrs.data.items) |existing| {
            if (existing.local_name.eql(attr.name)) {
                already_present = true;
                break;
            }
        }
        if (!already_present) try el.attrs.append(.{
            .ns = attr.namespace,
            .prefix = if (attr.prefix) |prefix| prefix.clone() else null,
            .local_name = attr.name.clone(),
            .value = attr.value.clone(),
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
    self.tree_adapter.handleError(err);
}

// https://html.spec.whatwg.org/multipage/parsing.html#reconstruct-the-active-formatting-elements
pub fn reconstructActiveFormattingElements(self: *TreeBuilder) void {
    if (self.active_fmt_els.len() == 0) return;
    var index = self.active_fmt_els.len() - 1;
    switch (self.active_fmt_els.at(index)) {
        .AFE_Marker => return,
        .AFE_Element => |el| if (std.mem.indexOfScalar(*Element, self.open_elements.els.items, el) != null) return,
    }
    while (index > 0) {
        switch (self.active_fmt_els.at(index - 1)) {
            .AFE_Marker => break,
            .AFE_Element => |el| if (std.mem.indexOfScalar(*Element, self.open_elements.els.items, el) != null) break,
        }
        index -= 1;
    }
    while (index < self.active_fmt_els.len()) : (index += 1) {
        const old = switch (self.active_fmt_els.at(index)) {
            .AFE_Element => |el| el,
            .AFE_Marker => unreachable,
        };
        const replacement = Element.create(self.document, old.local_name, old.ns, old.prefix, old.is, false, old.custom_element_registry);
        for (old.attrs.data.items) |attr| replacement.attrs.append(.{
            .ns = attr.ns,
            .prefix = attr.prefix,
            .local_name = attr.local_name,
            .value = attr.value.clone(),
            .element = null,
        }) catch @panic("out of memory");
        self.insertElementAtAdjustedInsertionLocation(replacement);
        self.open_elements.append(replacement) catch @panic("out of memory");
        self.active_fmt_els.setAt(index, .{ .AFE_Element = replacement });
    }
}

// https://html.spec.whatwg.org/multipage/parsing.html#close-a-p-element
pub fn closePElement(self: *TreeBuilder) void {
    self.generateImpliedEndTags(.p);
    if (!self.currentNode().local_name.is(.p)) self.parseError(.current_node_not_p);
    self.popUntilPopped(.p);
}

// Might need more logic here.
pub fn handleNewLine(self: *TreeBuilder) void {
    self.ignore_next_lf = true;
}

pub fn handleListItemStartTag(self: *TreeBuilder, tk: token_.Tag, tag: LocalTag) void {
    var i = self.open_elements.len();
    while (i > 0) {
        i -= 1;
        const node = self.open_elements.at(i);
        const closes = if (tag == .li)
            node.local_name.is(.li)
        else
            node.local_name.oneOf(&.{ .dd, .dt });
        if (closes) {
            self.generateImpliedEndTags(node.local_name.toTag());
            if (self.currentNode() != node) self.parseError(.unexpected_node);

            while (self.open_elements.len() > i) _ = self.open_elements.pop();
            break;
        }
        if (node.isSpecial() and !node.local_name.oneOf(&.{ .address, .div, .p })) break;
    }
    if (self.hasElementInButtonScope(.p)) self.closePElement();
    _ = self.insertHtmlElement_E(tk) catch @panic("out of memory");
}

fn optionalLocalNamesEqual(a: ?LocalName, b: ?LocalName) bool {
    if (a == null or b == null) return a == null and b == null;
    return std.mem.eql(u8, a.?.slice(), b.?.slice());
}

fn formattingElementsEquivalent(a: *const Element, b: *const Element) bool {
    if (a.ns != b.ns or
        !std.mem.eql(u8, a.local_name.slice(), b.local_name.slice()) or
        a.attrs.data.items.len != b.attrs.data.items.len)
    {
        return false;
    }

    for (a.attrs.data.items) |a_attr| {
        var matched = false;
        for (b.attrs.data.items) |b_attr| {
            if (a_attr.ns == b_attr.ns and
                optionalLocalNamesEqual(a_attr.prefix, b_attr.prefix) and
                std.mem.eql(u8, a_attr.local_name.slice(), b_attr.local_name.slice()) and
                std.mem.eql(u8, a_attr.value.slice(), b_attr.value.slice()))
            {
                matched = true;
                break;
            }
        }
        if (!matched) return false;
    }
    return true;
}

pub fn pushActiveFormattingElement(self: *TreeBuilder, el: *Element) void {
    var equivalent_count: usize = 0;
    var earliest_equivalent: ?usize = null;
    var i = self.active_fmt_els.len();
    while (i > 0) {
        i -= 1;
        switch (self.active_fmt_els.at(i)) {
            .AFE_Marker => break,
            .AFE_Element => |candidate| {
                if (formattingElementsEquivalent(candidate, el)) {
                    equivalent_count += 1;
                    earliest_equivalent = i;
                }
            },
        }
    }
    if (equivalent_count >= 3) _ = self.active_fmt_els.removeAt(earliest_equivalent.?);
    self.active_fmt_els.append(.{ .AFE_Element = el }) catch @panic("out of memory");
}

fn anyOtherEndTag(self: *TreeBuilder, subject: LocalName) void {
    var index = self.open_elements.len();
    while (index > 0) {
        index -= 1;
        const node = self.open_elements.at(index);
        const tag = subject.toTag();
        if (tag) |t| {
            if (node.ns == .NS_Html and node.local_name.is(t)) {
                self.generateImpliedEndTags(t);
                if (self.currentNode() != node) self.parseError(.unexpected_node);
                while (self.open_elements.len() > index) _ = self.open_elements.pop();
                return;
            }
        }
        if (node.isSpecial()) {
            self.parseError(.unexpected_node);
            return;
        }
    }
}

fn cloneElementForAdoption(self: *TreeBuilder, old: *Element) *Element {
    const replacement = Element.create(
        self.document,
        old.local_name.clone(),
        old.ns,
        if (old.prefix) |prefix| prefix.clone() else null,
        old.is,
        false,
        old.custom_element_registry,
    );
    for (old.attrs.data.items) |attr| replacement.attrs.append(.{
        .ns = attr.ns,
        .prefix = if (attr.prefix) |prefix| prefix.clone() else null,
        .local_name = attr.local_name.clone(),
        .value = attr.value.clone(),
        .element = null,
    }) catch @panic("out of memory");
    return replacement;
}

// https://html.spec.whatwg.org/multipage/parsing.html#adoption-agency-algorithm
pub fn adoptionAgencyAlgorithm(self: *TreeBuilder, tk: token_.Tag) void {
    const subject = tk.name.toTag() orelse return;
    if (self.currentNode().local_name.is(subject) and self.active_fmt_els.index(self.currentNode()) == null) {
        _ = self.open_elements.pop();
        return;
    }

    var outer_loop_counter: usize = 0;
    while (outer_loop_counter < 8) : (outer_loop_counter += 1) {
        const fmt_idx = self.active_fmt_els.lastWithTag(subject) orelse {
            self.anyOtherEndTag(tk.name);
            return;
        };
        const fmt_el = self.active_fmt_els.at(fmt_idx).AFE_Element;
        const fmt_stack_idx = self.open_elements.index(fmt_el) orelse {
            _ = self.active_fmt_els.removeAt(fmt_idx);
            return;
        };
        if (fmt_el.local_name.toTag()) |tag| {
            if (!self.open_elements.hasElementInScopeCustom(tag, &.{})) return;
        }

        var fur_block_idx: ?usize = null;
        var stack_idx = fmt_stack_idx + 1;
        while (stack_idx < self.open_elements.len()) : (stack_idx += 1) {
            if (self.open_elements.at(stack_idx).isSpecial()) {
                fur_block_idx = stack_idx;
                break;
            }
        }
        if (fur_block_idx == null) {
            while (self.open_elements.len() > fmt_stack_idx) _ = self.open_elements.pop();
            _ = self.active_fmt_els.removeAt(fmt_idx);
            return;
        }

        const fur_block = self.open_elements.at(fur_block_idx.?);
        const common_ancestor = self.open_elements.at(fmt_stack_idx - 1);
        var bookmark = fmt_idx;
        var node_idx = fur_block_idx.?;
        var last_node = fur_block;
        var inner_loop_counter: usize = 0;

        while (true) {
            inner_loop_counter += 1;
            node_idx -= 1;
            var node = self.open_elements.at(node_idx);
            if (node == fmt_el) break;

            var active_idx = self.active_fmt_els.index(node);
            if (inner_loop_counter > 3 and active_idx != null) {
                const removed_idx = active_idx.?;
                _ = self.active_fmt_els.removeAt(removed_idx);
                if (removed_idx < bookmark) bookmark -= 1;
                active_idx = null;
            }
            if (active_idx == null) {
                _ = self.open_elements.els.orderedRemove(node_idx);
                continue;
            }

            const replacement = self.cloneElementForAdoption(node);
            self.active_fmt_els.setAt(active_idx.?, .{ .AFE_Element = replacement });
            self.open_elements.setAt(node_idx, replacement);
            node = replacement;

            if (last_node == fur_block) bookmark = active_idx.? + 1;
            last_node.asNode().remove();
            node.asNode().appendChild(last_node.asNode());
            last_node = node;
        }

        const common_ancestor_location: InsertionLocation = .{ .last_child = common_ancestor.asNode() };
        const insertion_location = self.adjustedInsertionLocation(&common_ancestor_location);
        last_node.asNode().remove();
        self.insertNodeAt(last_node.asNode(), insertion_location);

        const new_element = self.cloneElementForAdoption(fmt_el);
        while (fur_block.asNode().first_child) |child| {
            fur_block.asNode().removeChild(child);
            new_element.asNode().appendChild(child);
        }
        fur_block.asNode().appendChild(new_element.asNode());

        if (self.active_fmt_els.index(fmt_el)) |old_idx| {
            _ = self.active_fmt_els.removeAt(old_idx);
            if (old_idx < bookmark) bookmark -= 1;
        }
        self.active_fmt_els.insertAt(bookmark, .{ .AFE_Element = new_element }) catch @panic("out of memory");

        _ = self.open_elements.remove(fmt_el);
        const cur_fur_idx = self.open_elements.index(fur_block).?;
        self.open_elements.insertAt(cur_fur_idx + 1, new_element) catch @panic("out of memory");
    }
}

pub inline fn unexpect(self: *TreeBuilder, tk: PendingToken, mode: InsertionMode) void {
    self.parseError(.{ .unexpected = .{ .tk = tk.token(), .mode = mode } });
}

pub fn debugDetail(self: *const TreeBuilder) void {
    _ = self;
}

/// A `null` mode means the token is processed or reprocessed using the current
/// `self.insert_mode`. A non-null mode temporarily overrides the insertion mode
/// for this call without modifying `self.insert_mode`.
pub fn step_E(self: *TreeBuilder, tk: PendingToken, mode: ?InsertionMode) !ProcessResult {
    switch (mode orelse self.insert_mode) {
        // https://html.spec.whatwg.org/multipage/parsing.html#the-initial-insertion-mode
        .InitialMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => return .PR_Done,
                    .NotWhitespace => break :sw,
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
                    if (!doc_tk.name.eql("html") or !doc_tk.public_id.isEmpty() or (!doc_tk.system_id.isEmpty() and !doc_tk.system_id.eql("about:legacy-compat"))) self.unexpect(tk, .InitialMode);
                    var dt = DocumentType.create(self.document, doc_tk.name.clone(), doc_tk.public_id.clone(), doc_tk.system_id.clone());
                    self.appendToDocument(dt.asNode());
                    if (!self.document.isIframeSrcdocDocument() and !self.document.parser_cannot_change_the_mode) {
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
            if (!self.document.isIframeSrcdocDocument()) self.parseError(.not_iframe_srcdoc);

            if (!self.document.parser_cannot_change_the_mode)
                self.document.mode = .DM_Quirks;

            self.insert_mode = .BeforeHtmlMode;
            // Reprocess.
            return self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#the-before-html-insertion-mode
        .BeforeHtmlMode => {
            sw: switch (tk) {
                .DoctypeToken => {
                    self.unexpect(tk, .BeforeHtmlMode);
                },
                .CommentToken => |cmt_tk| {
                    self.insertCommentToDocument(cmt_tk);
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstructionToDocument(pi_tk);
                    return .PR_Done;
                },
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => return .PR_Done,
                    .NotWhitespace => break :sw,
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) {
                                var html_elem = try self.createElementForToken_E(tag_tk, .NS_Html, self.document.asNode());
                                self.appendToDocument(html_elem.asNode());
                                try self.open_elements.append(html_elem);
                                self.insert_mode = .BeforeHeadMode;
                                return .PR_Done;
                            }
                            break :sw;
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.head) or tag_tk.name.is(.body) or tag_tk.name.is(.html) or tag_tk.name.is(.br)) {
                                break :sw;
                            }
                            self.unexpect(tk, .BeforeHtmlMode);
                        },
                    }
                },
                else => {},
            }

            // Anything else.
            var html_elem = Element.create(self.document, LocalName.fromTag(.html), .NS_Html, null, null, false, null);
            self.appendToDocument(html_elem.asNode());
            try self.open_elements.append(html_elem);
            self.insert_mode = .BeforeHeadMode;
            return self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#the-before-head-insertion-mode
        .BeforeHeadMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => return .PR_Done,
                    .NotWhitespace => break :sw,
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
                    self.unexpect(tk, .BeforeHeadMode);
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) {
                                return try self.step_E(tk, .InBodyMode);
                            } else if (tag_tk.name.is(.head)) {
                                const head_elem = try self.insertHtmlElement_E(tag_tk);
                                self.head_el_ptr = head_elem;
                                self.insert_mode = .InHeadMode;
                                return .PR_Done;
                            }
                            break :sw;
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.head) or tag_tk.name.is(.body) or tag_tk.name.is(.html) or tag_tk.name.is(.br)) {
                                break :sw;
                            }
                            self.unexpect(tk, .BeforeHeadMode);
                        },
                    }
                },
                else => {},
            }

            // Anything else
            const head_elem = try self.insertHtmlElement_E(.{
                .kind = .StartTag,
                .name = LocalName.fromTag(.head),
                .attrs = .empty,
                .self_closing = false,
            });
            self.head_el_ptr = head_elem;
            self.insert_mode = .InHeadMode;
            return self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inhead
        .InHeadMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => {
                        try self.insertCharacter_E(null, tk);
                        return .PR_Done;
                    },
                    .NotWhitespace => break :sw,
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
                    self.unexpect(tk, .InHeadMode);
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) {
                                return try self.step_E(tk, .InBodyMode);
                            } else if (tag_tk.name.is(.base) or tag_tk.name.is(.basefont) or tag_tk.name.is(.bgsound) or tag_tk.name.is(.link)) {
                                _ = try self.insertHtmlElement_E(tag_tk);
                                _ = self.open_elements.pop();
                                return .PR_AckSelfClosing;
                            } else if (tag_tk.name.is(.meta)) {
                                const elem = try self.insertHtmlElement_E(tag_tk);
                                _ = elem;
                                _ = self.open_elements.pop();
                                // TODO: need speculative html parser.
                                //                                if (elem.attrs.getFromLocalName(.charset)) |attr| {
                                //                                    const encoding = enc_map[attr.value.toLowerCase.slice()];
                                //                                } else {
                                //
                                //                                }
                                // TODO: Handle encoding.
                                return .PR_AckSelfClosing;
                            } else if (tag_tk.name.is(.title)) {
                                const state = try self.parseGenericTextElement_E(tag_tk, .TPT_Rcdata);
                                return .{ .PR_ChangeState = state };
                            } else if ((tag_tk.name.is(.noscript) and self.scripting_mode != .Disabled) or tag_tk.name.is(.noframes) or tag_tk.name.is(.style)) {
                                const state = try self.parseGenericTextElement_E(tag_tk, .TPT_Rawtext);
                                return .{ .PR_ChangeState = state };
                            } else if (tag_tk.name.is(.noscript) and self.scripting_mode == .Disabled) {
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.insert_mode = .InHeadNoscriptMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.script)) {
                                const adjust_loc = self.adjustedInsertionLocation(null);
                                const parent = adjust_loc.getParent();
                                const document = parent.node_doc;
                                const el = try self.createElementForToken_E(tag_tk, .NS_Html, document.asNode());
                                if (self.scripting_mode != .Fragment) el.parser_doc = self.document;
                                el.force_async = false;
                                if (self.scripting_mode == .Inert) el.already_started = true;
                                // TODO: Here ignore the step_E 6.
                                self.insertNodeAt(el.asNode(), adjust_loc);
                                try self.open_elements.append(el);
                                self.orig_insert_mode = self.insert_mode;
                                self.insert_mode = .TextMode;
                                return .{ .PR_ChangeState = .ScriptData };
                            } else if (tag_tk.name.is(.template)) {
                                const tmp_tag = tag_tk;
                                try self.active_fmt_els.append(.AFE_Marker);
                                self.frameset_ok = false;
                                self.insert_mode = .InTemplateMode;
                                try self.temp_insert_modes.append(self.allocator, .InTemplateMode);
                                const adjust_loc = self.adjustedInsertionLocation(null);
                                const intended_parent = adjust_loc.getParent();
                                self.document = intended_parent.node_doc;
                                if (tmp_tag.shadowRootMode() != .SRM_None) {
                                    if (!self.allow_decl_shadow_roots or self.isAdjustedCurrentNodeTopmost()) {
                                        _ = try self.insertHtmlElement_E(tag_tk);
                                        return .PR_Done;
                                    }

                                    const decl_she = self.adjustedCurrentNode();
                                    const temp = try self.insertForeignElement_E(tmp_tag, .NS_Html, true);
                                    const sr_mode = tmp_tag.shadowRootMode();
                                    var slot_ass: SlotAssignment = .SR_Named;
                                    if (tmp_tag.shadowRootSlotAssignment() == .SR_Manual) slot_ass = .SR_Manual;
                                    const clonable = tmp_tag.hasAttrName("shadowrootclonable");
                                    const serializable = tmp_tag.hasAttrName("shadowrootserializable");
                                    const delegate_focus = tmp_tag.hasAttrName("shadowrootdelegatesfocus");
                                    if (decl_she.shadow_root != null) {
                                        self.insertElementAt(temp, adjust_loc);
                                        return .PR_Done;
                                    }

                                    const registry =
                                        if (tmp_tag.hasAttrName("shadowrootcustomelementregistry"))
                                            null
                                        else
                                            decl_she.asNode().node_doc.custom_element_registry;
                                    decl_she.attachShadowRoot(sr_mode, clonable, serializable, delegate_focus, slot_ass, registry) catch {
                                        self.insertElementAt(temp, adjust_loc);
                                        // TODO: Optionally report the error.
                                        return .PR_Done;
                                    };
                                    const shadow = decl_she.shadow_root.?;
                                    shadow.available = true;
                                    shadow.declarative = true;
                                    if (temp.temp_contents_owned) {
                                        const old_contents = temp.temp_contents.?;
                                        old_contents.node.destroy(self.allocator);
                                        self.allocator.destroy(old_contents);
                                    }
                                    temp.temp_contents = &shadow.doc_frag;
                                    temp.temp_contents_owned = false;
                                    if (tmp_tag.hasAttrName("shadowrootcustomelementregistry"))
                                        shadow.keep_cer_null = true;
                                    return .PR_Done;
                                } else if (tmp_tag.hasAttrName("for")) {
                                    // Content patching is not supported by this DOM yet, so
                                    // prepare content patching necessarily returns false. Apply
                                    // the specification's failure path, undoing the stack-only
                                    // insertion and inserting the template at the saved location.
                                    const template = try self.insertForeignElement_E(tmp_tag, .NS_Html, true);
                                    std.debug.assert(self.open_elements.pop() == template);
                                    self.insertElementAt(template, adjust_loc);
                                    try self.open_elements.append(template);
                                } else {
                                    _ = try self.insertHtmlElement_E(tag_tk);
                                }
                                return .PR_Done;
                            } else if (tag_tk.name.is(.head)) {
                                self.unexpect(tk, .InHeadMode);
                                return .PR_Done;
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.head)) {
                                _ = self.open_elements.pop();
                                self.insert_mode = .AfterHeadMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.template)) {
                                if (!self.hasElement(.template)) {
                                    self.parseError(.no_element_on_stack);
                                    return .PR_Done;
                                }
                                self.generateAllImpliedEndTagsThoroughly();
                                if (self.currentNode().local_name.is(.template)) self.parseError(.end_tag_not_template);
                                self.popUntilPopped(.template);
                                self.clearActiveFormattingElementsToLastMarker();
                                _ = self.temp_insert_modes.pop();
                                self.resetInsertionModeAppropriately();
                            } else if (tag_tk.name.is(.body) or tag_tk.name.is(.html) or tag_tk.name.is(.br)) {
                                break :sw;
                            }
                            self.unexpect(tk, .InHeadMode);
                            return .PR_Done;
                        },
                    }
                },
                else => break :sw,
            }

            // Anything else
            _ = self.open_elements.pop();
            self.insert_mode = .AfterHeadMode;
            return try self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inheadnoscript
        .InHeadNoscriptMode => {
            switch (tk) {
                .DoctypeToken => {
                    self.unexpect(tk, .InHeadNoscriptMode);
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) {
                                return try self.step_E(tk, .InBodyMode);
                            }
                            if (tag_tk.name.oneOf(&.{ .basefont, .bgsound, .link, .meta, .noframes, .style })) return try self.step_E(tk, .InHeadMode);
                            if (tag_tk.name.oneOf(&.{ .head, .noscript })) {
                                self.unexpect(tk, .InHeadNoscriptMode);
                                return .PR_Done;
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.noscript)) {
                                _ = self.open_elements.pop();
                                self.insert_mode = .InHeadMode;
                                return .PR_Done;
                            }
                            if (!tag_tk.name.is(.br)) {
                                self.unexpect(tk, .InHeadNoscriptMode);
                                return .PR_Done;
                            }
                        },
                    }
                },
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => return try self.step_E(tk, .InHeadMode),
                    .NotWhitespace => {},
                },
                .CommentToken => {
                    return try self.step_E(tk, .InHeadMode);
                },
                .ProcessingInstructionToken => {
                    return try self.step_E(tk, .InHeadMode);
                },
                else => {},
            }

            // Anything else
            self.unexpect(tk, .InHeadNoscriptMode);
            _ = self.open_elements.pop();
            self.insert_mode = .InHeadMode;
            _ = try self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#the-after-head-insertion-mode
        .AfterHeadMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => {
                        try self.insertCharacter_E(null, tk);
                        return .PR_Done;
                    },
                    .NotWhitespace => break :sw,
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
                    self.unexpect(tk, .AfterHeadMode);
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) {
                                return try self.step_E(tk, .InBodyMode);
                            } else if (tag_tk.name.is(.body)) {
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.frameset_ok = false;
                                self.insert_mode = .InBodyMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.frameset)) {
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.insert_mode = .InFramesetMode;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title })) {
                                self.unexpect(tk, .AfterHeadMode);
                                const head_el = self.head_el_ptr.?;
                                try self.open_elements.append(head_el);
                                const res = try self.step_E(tk, .InHeadMode);
                                _ = self.open_elements.remove(head_el);
                                return res;
                            } else if (tag_tk.name.is(.head)) {
                                self.unexpect(tk, .AfterHeadMode);
                                return .PR_Done;
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.template)) {
                                return try self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.is(.body) or tag_tk.name.is(.html) or tag_tk.name.is(.br)) {
                                break :sw;
                            }
                            self.unexpect(tk, .AfterHeadMode);
                        },
                    }
                },
                else => {},
            }

            // Anything else
            _ = try self.insertHtmlElement_E(.{
                .kind = .StartTag,
                .name = LocalName.fromTag(.body),
                .attrs = .empty,
                .self_closing = false,
            });
            self.insert_mode = .InBodyMode;
            return try self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inbody
        .InBodyMode => {
            switch (tk) {
                .CharacterToken => {
                    try self.processCharacterTokenIgnoringNull_E(tk, processInBodyCharacterRun_E);
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
                    self.unexpect(tk, .InBodyMode);
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) {
                                self.unexpect(tk, .InBodyMode);
                                if (self.hasElement(.template)) return .PR_Done;
                                try self.addAttributesToElement_E(self.open_elements.at(0), tag_tk.attrs.items);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title })) {
                                return try self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.is(.body)) {
                                self.unexpect(tk, .InBodyMode);
                                if (self.open_elements.len() == 1 or !self.open_elements.at(1).local_name.is(.body) or self.hasElement(.template)) {
                                    return .PR_Done;
                                }
                                self.frameset_ok = false;
                                try self.addAttributesToElement_E(self.open_elements.at(1), tag_tk.attrs.items);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.frameset)) {
                                self.unexpect(tk, .InBodyMode);
                                if (self.open_elements.len() == 1 or !self.open_elements.at(1).local_name.is(.body) or !self.frameset_ok) {
                                    return .PR_Done;
                                }
                                if (self.open_elements.len() >= 2) {
                                    const second = self.open_elements.at(1);
                                    if (second.asNode().parent) |parent|
                                        parent.removeChild(second.asNode());
                                }
                                self.popUntil(.html);
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.insert_mode = .InFramesetMode;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .address, .article, .aside, .blockquote, .center, .details, .dialog, .dir, .div, .dl, .fieldset, .figcaption, .figure, .footer, .header, .hgroup, .main, .menu, .nav, .ol, .p, .search, .section, .summary, .ul })) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .h1, .h2, .h3, .h4, .h5, .h6 })) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                const cur_node = self.currentNode();
                                if (cur_node.ns == .NS_Html and cur_node.local_name.oneOf(&.{ .h1, .h2, .h3, .h4, .h5, .h6 })) {
                                    self.unexpect(tk, .InBodyMode);
                                    _ = self.open_elements.pop();
                                }
                                _ = try self.insertHtmlElement_E(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .pre, .listing })) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                // Handle newline at the start of block
                                self.handleNewLine();
                                self.frameset_ok = false;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.form)) {
                                if (self.form_el_ptr != null and !self.hasElement(.template)) {
                                    self.unexpect(tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                const element = try self.insertHtmlElement_E(tag_tk);
                                if (!self.hasElement(.template)) self.form_el_ptr = element;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.li)) {
                                self.frameset_ok = false;
                                self.handleListItemStartTag(tag_tk, .li);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .dd, .dt })) {
                                self.frameset_ok = false;
                                self.handleListItemStartTag(tag_tk, tag_tk.name.toTag().?);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.plaintext)) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                return .{ .PR_ChangeState = .PLAINTEXT };
                            } else if (tag_tk.name.is(.button)) {
                                if (self.hasElementInScope(.button)) {
                                    self.unexpect(tk, .InBodyMode);
                                    self.generateImpliedEndTags(null);
                                    self.popUntilPopped(.button);
                                }
                                self.reconstructActiveFormattingElements();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.frameset_ok = false;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.a)) {
                                if (self.active_fmt_els.lastWithTag(.a)) |old_idx| {
                                    const old_anchor = self.active_fmt_els.at(old_idx).AFE_Element;
                                    self.unexpect(tk, .InBodyMode);
                                    self.adoptionAgencyAlgorithm(tag_tk);
                                    if (self.active_fmt_els.index(old_anchor)) |remaining_idx|
                                        _ = self.active_fmt_els.removeAt(remaining_idx);
                                    _ = self.open_elements.remove(old_anchor);
                                }
                                self.reconstructActiveFormattingElements();
                                const element = try self.insertHtmlElement_E(tag_tk);
                                self.pushActiveFormattingElement(element);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .b, .big, .code, .em, .font, .i, .s, .small, .strike, .strong, .tt, .u })) {
                                self.reconstructActiveFormattingElements();
                                const element = try self.insertHtmlElement_E(tag_tk);
                                self.pushActiveFormattingElement(element);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.nobr)) {
                                self.reconstructActiveFormattingElements();
                                if (self.hasElementInScope(.nobr)) {
                                    self.unexpect(tk, .InBodyMode);
                                    self.adoptionAgencyAlgorithm(tag_tk);
                                    self.reconstructActiveFormattingElements();
                                }
                                const element = try self.insertHtmlElement_E(tag_tk);
                                self.pushActiveFormattingElement(element);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .applet, .marquee, .object })) {
                                self.reconstructActiveFormattingElements();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                try self.active_fmt_els.append(.AFE_Marker);
                                self.frameset_ok = false;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.table)) {
                                if (self.document.mode != .DM_Quirks and self.hasElementInButtonScope(.p))
                                    self.closePElement();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.frameset_ok = false;
                                self.insert_mode = .InTableMode;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .area, .br, .embed, .img, .keygen, .wbr })) {
                                self.reconstructActiveFormattingElements();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                _ = self.open_elements.pop();
                                self.frameset_ok = false;
                                if (tag_tk.self_closing) return .PR_AckSelfClosing;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.input)) {
                                if (self.fragment_case and self.context.?.local_name.is(.select)) {
                                    self.unexpect(tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                if (self.hasElementInScope(.select)) {
                                    self.unexpect(tk, .InBodyMode);
                                    self.popUntilPopped(.select);
                                }
                                self.reconstructActiveFormattingElements();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                _ = self.open_elements.pop();
                                if (tag_tk.self_closing) return .PR_AckSelfClosing;

                                const is_hidden = if (tag_tk.getAttrVal("type")) |v|
                                    v.eqlIgnoreCase("hidden")
                                else
                                    false;

                                if (!is_hidden) self.frameset_ok = false;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .param, .source, .track })) {
                                _ = try self.insertHtmlElement_E(tag_tk);
                                _ = self.open_elements.pop();
                                if (tag_tk.self_closing) return .PR_AckSelfClosing;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.hr)) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                _ = self.open_elements.pop();
                                if (tag_tk.self_closing) return .PR_AckSelfClosing;
                                self.frameset_ok = false;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.image)) {
                                self.unexpect(tk, .InBodyMode);
                                var mut_tk = tk;
                                mut_tk.TagToken.name = LocalName.fromTag(.img);
                                return try self.step_E(mut_tk, null);
                            } else if (tag_tk.name.is(.textarea)) {
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.handleNewLine();
                                self.orig_insert_mode = self.insert_mode;
                                self.frameset_ok = false;
                                self.insert_mode = .TextMode;
                                return .{ .PR_ChangeState = .RCDATA };
                            } else if (tag_tk.name.is(.xmp)) {
                                if (self.hasElementInButtonScope(.p)) self.closePElement();
                                self.reconstructActiveFormattingElements();
                                self.frameset_ok = false;
                                const state = try self.parseGenericTextElement_E(tag_tk, .TPT_Rawtext);
                                return .{ .PR_ChangeState = state };
                            } else if (tag_tk.name.is(.iframe)) {
                                self.frameset_ok = false;
                                const state = try self.parseGenericTextElement_E(tag_tk, .TPT_Rawtext);
                                return .{ .PR_ChangeState = state };
                            } else if (tag_tk.name.is(.noembed) or (tag_tk.name.is(.noscript) and self.scripting_mode != .Disabled)) {
                                const state = try self.parseGenericTextElement_E(tag_tk, .TPT_Rawtext);
                                return .{ .PR_ChangeState = state };
                            } else if (tag_tk.name.is(.select)) {
                                if (self.fragment_case) {
                                    // TODO;
                                    self.parseError(.unexpected_node);
                                    return .PR_Done;
                                } else if (self.open_elements.hasElementInScopeCustom(.select, &.{})) {
                                    self.parseError(.unexpected_node);

                                    self.popUntilPopped(.select);
                                    return .PR_Done;
                                } else {
                                    self.reconstructActiveFormattingElements();
                                    _ = try self.insertHtmlElement_E(tag_tk);
                                    self.frameset_ok = false;
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.is(.option)) {
                                if (self.hasElementInScope(.select)) {
                                    self.generateImpliedEndTags(.optgroup);
                                    if (self.hasElementInScope(.option))
                                        self.parseError(.unexpected_node);
                                } else if (self.currentNode().local_name.is(.option)) {
                                    _ = self.open_elements.pop();
                                }
                                self.reconstructActiveFormattingElements();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.optgroup)) {
                                if (self.hasElementInScope(.select)) {
                                    self.generateImpliedEndTags(null);
                                    if (self.hasElementInScope(.option) or self.hasElementInScope(.optgroup))
                                        self.parseError(.unexpected_node);
                                } else if (self.currentNode().local_name.is(.option)) {
                                    _ = self.open_elements.pop();
                                }
                                self.reconstructActiveFormattingElements();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .rb, .rtc })) {
                                if (self.hasElementInScope(.ruby)) self.generateImpliedEndTags(null);
                                _ = try self.insertHtmlElement_E(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .rp, .rt })) {
                                if (self.hasElementInScope(.ruby)) self.generateImpliedEndTags(.rtc);
                                _ = try self.insertHtmlElement_E(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.math)) {
                                self.reconstructActiveFormattingElements();

                                var adjusted_tag = tag_tk;
                                adjusted_tag.adjustMathMLAttributes();
                                adjusted_tag.adjustForeignAttributes();
                                _ = try self.insertForeignElement_E(adjusted_tag, .NS_Math, false);
                                if (adjusted_tag.self_closing) {
                                    _ = self.open_elements.pop();
                                    return .PR_AckSelfClosing;
                                }
                                return .PR_Done;
                            } else if (tag_tk.name.is(.svg)) {
                                self.reconstructActiveFormattingElements();

                                var adjusted_tag = tag_tk;
                                adjusted_tag.adjustSVGAttributes();
                                adjusted_tag.adjustForeignAttributes();
                                _ = try self.insertForeignElement_E(adjusted_tag, .NS_Svg, false);
                                if (adjusted_tag.self_closing) {
                                    _ = self.open_elements.pop();
                                    return .PR_AckSelfClosing;
                                }
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .caption, .col, .colgroup, .frame, .head, .tbody, .td, .tfoot, .th, .thead, .tr })) {
                                self.unexpect(tk, .InBodyMode);
                                return .PR_Done;
                            }

                            // Any other start tag
                            self.reconstructActiveFormattingElements();
                            _ = try self.insertHtmlElement_E(tag_tk);
                            return .PR_Done;
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.template)) {
                                return try self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.is(.body)) {
                                if (!self.hasElementInScope(.body)) {
                                    self.unexpect(tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                if (self.allElementsOneOf(&.{ .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc, .tbody, .td, .tfoot, .th, .thead, .tr, .body, .html }))
                                    self.insert_mode = .AfterBodyMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.html)) {
                                if (!self.hasElementInScope(.body)) {
                                    self.unexpect(tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.insert_mode = .AfterBodyMode;
                                return try self.step_E(tk, null);
                            } else if (tag_tk.name.oneOf(&.{ .address, .article, .aside, .blockquote, .button, .center, .details, .dialog, .dir, .div, .dl, .fieldset, .figcaption, .figure, .footer, .header, .hgroup, .listing, .main, .menu, .nav, .ol, .pre, .search, .section, .select, .summary, .ul })) {
                                const tag = tag_tk.name.toTag().?;
                                if (!self.hasElementInScope(tag)) {
                                    self.unexpect(tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.generateImpliedEndTags(null);
                                if (!self.currentNode().local_name.is(tag))
                                    self.unexpect(tk, .InBodyMode);
                                self.popUntilPopped(tag);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.form)) {
                                if (!self.hasElement(.template)) {
                                    const node = self.form_el_ptr;
                                    self.form_el_ptr = null;
                                    if (node == null or !self.hasElementInScope(node.?.local_name.toTag().?)) {
                                        self.unexpect(tk, .InBodyMode);
                                        return .PR_Done;
                                    }
                                    self.generateImpliedEndTags(null);
                                    if (self.currentNode() != node.?)
                                        self.unexpect(tk, .InBodyMode);
                                    _ = self.open_elements.remove(node.?);
                                } else {
                                    if (!self.hasElementInScope(.form)) {
                                        self.unexpect(tk, .InBodyMode);
                                        return .PR_Done;
                                    }
                                    self.generateImpliedEndTags(null);
                                    if (!self.currentNode().local_name.is(.form))
                                        self.unexpect(tk, .InBodyMode);
                                    self.popUntilPopped(.form);
                                }
                                return .PR_Done;
                            } else if (tag_tk.name.is(.p)) {
                                if (!self.hasElementInButtonScope(.p)) {
                                    self.unexpect(tk, .InBodyMode);
                                    _ = try self.insertHtmlElement_E(.{
                                        .kind = .StartTag,
                                        .name = LocalName.fromTag(.p),
                                        .attrs = .empty,
                                        .self_closing = false,
                                    });
                                }
                                self.closePElement();
                                return .PR_Done;
                            } else if (tag_tk.name.is(.li)) {
                                if (!self.hasElementInListItemScope(.li)) {
                                    self.unexpect(tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.generateImpliedEndTags(.li);
                                if (!self.currentNode().local_name.is(.li))
                                    self.unexpect(tk, .InBodyMode);
                                self.popUntilPopped(.li);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .dd, .dt })) {
                                const tag = tag_tk.name.toTag().?;
                                if (!self.hasElementInScope(tag)) {
                                    self.unexpect(tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.generateImpliedEndTags(tag);
                                if (!self.currentNode().local_name.is(tag))
                                    self.unexpect(tk, .InBodyMode);
                                self.popUntilPopped(tag);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .h1, .h2, .h3, .h4, .h5, .h6 })) {
                                if (!self.allElementsOneOf(&.{ .h1, .h2, .h3, .h4, .h5, .h6 })) {
                                    self.unexpect(tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.generateImpliedEndTags(null);
                                if (!self.currentNode().local_name.is(tag_tk.name.toTag().?))
                                    self.unexpect(tk, .InBodyMode);
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
                                const tag = tag_tk.name.toTag().?;
                                if (!self.hasElementInScope(tag)) {
                                    self.unexpect(tk, .InBodyMode);
                                    return .PR_Done;
                                }
                                self.generateImpliedEndTags(null);
                                if (!self.currentNode().local_name.is(tag))
                                    self.unexpect(tk, .InBodyMode);
                                self.popUntilPopped(tag);
                                self.clearActiveFormattingElementsToLastMarker();
                                return .PR_Done;
                            } else if (tag_tk.name.is(.br)) {
                                self.unexpect(tk, .InBodyMode);
                                var mut_tk = tk;
                                mut_tk.TagToken.kind = .StartTag;
                                return try self.step_E(mut_tk, null);
                            }

                            self.anyOtherEndTag(tag_tk.name);
                            return .PR_Done;
                        },
                    }
                },
                .EofToken => {
                    if (self.temp_insert_modes.items.len > 0) return try self.step_E(tk, .InTemplateMode);

                    if (self.allElementsOneOf(&.{ .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc, .tbody, .td, .tfoot, .th, .thead, .tr, .body, .html })) self.parseError(.unexpected_node);
                    return .PR_StopParsing;
                },
                else => {},
            }
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-incdata
        .TextMode => {
            switch (tk) {
                .CharacterToken => {
                    try self.insertCharacter_E(null, tk);
                    return .PR_Done;
                },
                .EofToken => {
                    self.unexpect(tk, .TextMode);
                    const node = self.currentNode();
                    if (node.local_name.is(.script)) {
                        node.already_started = true;
                    }
                    _ = self.open_elements.pop();
                    self.insert_mode = self.orig_insert_mode;
                    return try self.step_E(tk, null);
                },
                .TagToken => |tag_tk| {
                    if (tag_tk.kind == .EndTag) {
                        if (tag_tk.name.is(.script)) {
                            // TODO: need script.
                            _ = self.open_elements.pop();
                            self.insert_mode = self.orig_insert_mode;
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
                        self.pending_table_char_tks.clearRetainingCapacity();
                        self.orig_insert_mode = self.insert_mode;
                        self.insert_mode = .InTableTextMode;
                        return try self.step_E(tk, null);
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
                    self.unexpect(tk, .InTableMode);
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.caption)) {
                                self.clearStackBackToTableContext();
                                try self.active_fmt_els.append(.AFE_Marker);
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.insert_mode = .InCaptionMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.colgroup)) {
                                self.clearStackBackToTableContext();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.insert_mode = .InColumnGroupMode;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.col)) {
                                self.clearStackBackToTableContext();
                                _ = try self.insertHtmlElement_E(.{
                                    .kind = .StartTag,
                                    .name = LocalName.fromTag(.colgroup),
                                    .attrs = .empty,
                                    .self_closing = false,
                                });
                                self.insert_mode = .InColumnGroupMode;
                                return try self.step_E(tk, null);
                            } else if (tag_tk.name.oneOf(&.{ .tbody, .tfoot, .thead })) {
                                self.clearStackBackToTableContext();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.insert_mode = .InTableBodyMode;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .td, .th, .tr })) {
                                self.clearStackBackToTableContext();
                                _ = try self.insertHtmlElement_E(.{
                                    .kind = .StartTag,
                                    .name = LocalName.fromTag(.tbody),
                                    .attrs = .empty,
                                    .self_closing = false,
                                });
                                self.insert_mode = .InTableBodyMode;
                                return try self.step_E(tk, null);
                            } else if (tag_tk.name.is(.table)) {
                                self.unexpect(tk, .InTableMode);
                                if (!self.hasElementInTableScope(.table)) {
                                    return .PR_Done;
                                } else {
                                    self.popUntilPopped(.table);
                                    self.resetInsertionModeAppropriately();
                                    return try self.step_E(tk, null);
                                }
                            } else if (tag_tk.name.oneOf(&.{ .style, .script, .template })) {
                                return try self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.is(.input)) {
                                const is_hidden = if (tag_tk.getAttrVal("type")) |v|
                                    v.eqlIgnoreCase("hidden")
                                else
                                    false;

                                if (!is_hidden) break :sw;

                                self.parseError(.non_hidden_input);
                                _ = try self.insertHtmlElement_E(tag_tk);
                                _ = self.open_elements.pop();
                                if (tag_tk.self_closing) return .PR_AckSelfClosing;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.form)) {
                                self.unexpect(tk, .InTableMode);
                                if (self.hasElement(.template) or self.form_el_ptr != null) {
                                    return .PR_Done;
                                } else {
                                    const form_elem = try self.insertHtmlElement_E(tag_tk);
                                    self.form_el_ptr = form_elem;
                                    _ = self.open_elements.pop();
                                    return .PR_Done;
                                }
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.table)) {
                                if (!self.hasElementInTableScope(.table)) {
                                    self.parseError(.no_table_in_scope);
                                    return .PR_Done;
                                } else {
                                    self.popUntilPopped(.table);
                                    self.resetInsertionModeAppropriately();
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.is(.template)) {
                                return try self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.oneOf(&.{ .body, .caption, .col, .colgroup, .html, .tbody, .td, .tfoot, .th, .thead, .tr })) {
                                self.parseError(.invalid_start_tag_in_insertion_mode);
                                return .PR_Done;
                            }
                        },
                    }
                },
                .EofToken => {
                    return try self.step_E(tk, .InBodyMode);
                },
                else => {},
            }

            // Anything else
            self.unexpect(tk, .InTableMode);
            self.foster_parenting = true;
            const res = try self.step_E(tk, .InBodyMode);
            self.foster_parenting = false;
            return res;
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intabletext
        .InTableTextMode => {
            switch (tk) {
                .CharacterToken => {
                    try self.processCharacterTokenIgnoringNull_E(tk, bufferTableCharacterRun_E);
                    return .PR_Done;
                },
                else => {},
            }

            // Anything else
            var contains_non_whitespace = false;
            for (self.pending_table_char_tks.items) |pending_tk| {
                if (pending_tk == .CharacterToken) {
                    for (pending_tk.CharacterToken.slice()) |c| {
                        if (!ascii.isAsciiWhitespace(u8, c)) {
                            contains_non_whitespace = true;
                            break;
                        }
                    }
                }
                if (contains_non_whitespace) break;
            }

            if (contains_non_whitespace) {
                self.parseError(.non_whitespace_in_table_text);
                for (self.pending_table_char_tks.items) |pending_tk| {
                    // Using the rules given in the `anything else` in the `in table` insertion mode.
                    self.foster_parenting = true;
                    _ = try self.step_E(pending_tk, .InBodyMode);
                    self.foster_parenting = false;
                }
            } else {
                for (self.pending_table_char_tks.items) |pending_tk| {
                    if (pending_tk == .CharacterToken)
                        try self.insertCharacter_E(null, pending_tk);
                }
            }

            for (self.pending_table_char_tks.items) |*pending_tk| pending_tk.deinit(self.allocator);
            self.pending_table_char_tks.clearRetainingCapacity();
            self.insert_mode = self.orig_insert_mode;
            return try self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-incaption
        .InCaptionMode => {
            switch (tk) {
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.oneOf(&.{ .caption, .col, .colgroup, .tbody, .td, .tfoot, .th, .thead, .tr })) {
                                if (!self.hasElementInTableScope(.caption)) {
                                    self.parseError(.no_caption_in_table_scope);
                                    return .PR_Done;
                                } else {
                                    self.generateImpliedEndTags(null);
                                    if (!self.currentNode().local_name.is(.caption))
                                        self.parseError(.current_node_not_caption);
                                    self.popUntilPopped(.caption);
                                    self.clearActiveFormattingElementsToLastMarker();
                                    self.insert_mode = .InTableMode;
                                    return try self.step_E(tk, null);
                                }
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.caption)) {
                                if (!self.hasElementInTableScope(.caption)) {
                                    self.parseError(.no_caption_in_table_scope);
                                    return .PR_Done;
                                } else {
                                    self.generateImpliedEndTags(null);
                                    if (!self.currentNode().local_name.is(.caption))
                                        self.parseError(.current_node_not_caption);
                                    self.popUntilPopped(.caption);
                                    self.clearActiveFormattingElementsToLastMarker();
                                    self.insert_mode = .InTableMode;
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.is(.table)) {
                                if (!self.hasElementInTableScope(.caption)) {
                                    self.parseError(.no_caption_in_table_scope);
                                    return .PR_Done;
                                } else {
                                    self.generateImpliedEndTags(null);
                                    if (!self.currentNode().local_name.is(.caption))
                                        self.parseError(.current_node_not_caption);
                                    self.popUntilPopped(.caption);
                                    self.clearActiveFormattingElementsToLastMarker();
                                    self.insert_mode = .InTableMode;
                                    return try self.step_E(tk, null);
                                }
                            } else if (tag_tk.name.oneOf(&.{ .body, .col, .colgroup, .html, .tbody, .td, .tfoot, .th, .thead, .tr })) {
                                self.parseError(.invalid_tag_in_caption);
                                return .PR_Done;
                            }
                        },
                    }
                },
                else => {},
            }

            // Anything else
            return try self.step_E(tk, .InBodyMode);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-incolgroup
        .InColumnGroupMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => {
                        try self.insertCharacter_E(null, tk);
                        return .PR_Done;
                    },
                    .NotWhitespace => break :sw,
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
                    self.unexpect(tk, .InColumnGroupMode);
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) {
                                return try self.step_E(tk, .InBodyMode);
                            } else if (tag_tk.name.is(.col)) {
                                _ = try self.insertHtmlElement_E(tag_tk);
                                _ = self.open_elements.pop();
                                if (tag_tk.self_closing) return .PR_AckSelfClosing;
                                return .PR_Done;
                            } else if (tag_tk.name.is(.template)) {
                                return try self.step_E(tk, .InHeadMode);
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.colgroup)) {
                                if (!self.currentNode().local_name.is(.colgroup)) {
                                    self.parseError(.current_node_not_colgroup);
                                    return .PR_Done;
                                } else {
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableMode;
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.is(.col)) {
                                self.parseError(.invalid_tag_in_column_group);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.template)) {
                                return try self.step_E(tk, .InHeadMode);
                            }
                        },
                    }
                },
                .EofToken => {
                    return try self.step_E(tk, .InBodyMode);
                },
                else => {},
            }

            // Anything else
            if (!self.currentNode().local_name.is(.colgroup)) {
                self.parseError(.current_node_not_colgroup);
                return .PR_Done;
            } else {
                _ = self.open_elements.pop();
                self.insert_mode = .InTableMode;
                return try self.step_E(tk, null);
            }
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intbody
        .InTableBodyMode => {
            switch (tk) {
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.tr)) {
                                self.clearStackBackToTableBodyContext();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.insert_mode = .InRowMode;
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .th, .td })) {
                                self.parseError(.unexpected_td_th_in_table_body);
                                self.clearStackBackToTableBodyContext();
                                _ = try self.insertHtmlElement_E(.{
                                    .kind = .StartTag,
                                    .name = LocalName.fromTag(.tr),
                                    .attrs = .empty,
                                    .self_closing = false,
                                });
                                self.insert_mode = .InRowMode;
                                return try self.step_E(tk, null);
                            } else if (tag_tk.name.oneOf(&.{ .caption, .col, .colgroup, .tbody, .tfoot, .thead })) {
                                if (!self.hasElementInTableScope(.tbody) and
                                    !self.hasElementInTableScope(.thead) and
                                    !self.hasElementInTableScope(.tfoot))
                                {
                                    self.parseError(.no_table_section_in_scope);
                                    return .PR_Done;
                                } else {
                                    self.clearStackBackToTableBodyContext();
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableMode;
                                    return try self.step_E(tk, null);
                                }
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.oneOf(&.{ .tbody, .tfoot, .thead })) {
                                if (!self.hasElementInTableScope(tag_tk.name.toTag().?)) {
                                    self.parseError(.no_table_section_in_scope);
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
                                    self.parseError(.no_table_section_in_scope);
                                    return .PR_Done;
                                } else {
                                    self.clearStackBackToTableBodyContext();
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableMode;
                                    return try self.step_E(tk, null);
                                }
                            } else if (tag_tk.name.oneOf(&.{ .body, .caption, .col, .colgroup, .html, .td, .th, .tr })) {
                                self.parseError(.invalid_tag_in_table_body);
                                return .PR_Done;
                            }
                        },
                    }
                },
                else => {},
            }

            // Anything else
            return try self.step_E(tk, .InTableMode);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intr
        .InRowMode => {
            switch (tk) {
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.oneOf(&.{ .th, .td })) {
                                self.clearStackBackToTableRowContext();
                                _ = try self.insertHtmlElement_E(tag_tk);
                                self.insert_mode = .InCellMode;
                                try self.active_fmt_els.append(.AFE_Marker);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .caption, .col, .colgroup, .tbody, .tfoot, .thead, .tr })) {
                                if (!self.hasElementInTableScope(.tr)) {
                                    self.parseError(.no_tr_in_table_scope);
                                    return .PR_Done;
                                } else {
                                    self.clearStackBackToTableRowContext();
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableBodyMode;
                                    return try self.step_E(tk, null);
                                }
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.tr)) {
                                if (!self.hasElementInTableScope(.tr)) {
                                    self.parseError(.no_tr_in_table_scope);
                                    return .PR_Done;
                                } else {
                                    self.clearStackBackToTableRowContext();
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableBodyMode;
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.is(.table)) {
                                if (!self.hasElementInTableScope(.tr)) {
                                    self.parseError(.no_tr_in_table_scope);
                                    return .PR_Done;
                                } else {
                                    self.clearStackBackToTableRowContext();
                                    _ = self.open_elements.pop();
                                    self.insert_mode = .InTableBodyMode;
                                    return try self.step_E(tk, null);
                                }
                            } else if (tag_tk.name.oneOf(&.{ .tbody, .tfoot, .thead })) {
                                if (!self.hasElementInTableScope(tag_tk.name.toTag().?)) {
                                    self.parseError(.end_table_section_without_scope);
                                    return .PR_Done;
                                }

                                if (!self.hasElementInTableScope(.tr)) return .PR_Done;

                                self.clearStackBackToTableRowContext();
                                _ = self.open_elements.pop();
                                self.insert_mode = .InTableBodyMode;
                                return try self.step_E(tk, null);
                            } else if (tag_tk.name.oneOf(&.{ .body, .caption, .col, .colgroup, .html, .td, .th })) {
                                self.parseError(.invalid_end_tag_in_row);
                                return .PR_Done;
                            }
                        },
                    }
                },
                else => {},
            }

            // Anything else
            return try self.step_E(tk, .InTableMode);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intd
        .InCellMode => {
            switch (tk) {
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.oneOf(&.{ .caption, .col, .colgroup, .tbody, .td, .tfoot, .th, .thead, .tr })) {
                                std.debug.assert(self.hasElementInTableScope(.td) or self.hasElementInTableScope(.th));
                                self.closeCell();
                                return try self.step_E(tk, null);
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.oneOf(&.{ .td, .th })) {
                                const target_tag = tag_tk.name.toTag().?;
                                if (!self.hasElementInTableScope(target_tag)) {
                                    self.parseError(.end_cell_without_cell_in_scope);
                                    return .PR_Done;
                                } else {
                                    self.generateImpliedEndTags(null);
                                    if (!self.currentNode().local_name.is(target_tag))
                                        self.parseError(.current_node_not_cell);
                                    self.popUntilPopped(target_tag);
                                    self.clearActiveFormattingElementsToLastMarker();
                                    self.insert_mode = .InRowMode;
                                    return .PR_Done;
                                }
                            } else if (tag_tk.name.oneOf(&.{ .body, .caption, .col, .colgroup, .html })) {
                                self.parseError(.invalid_tag_in_cell);
                                return .PR_Done;
                            } else if (tag_tk.name.oneOf(&.{ .table, .tbody, .tfoot, .thead, .tr })) {
                                if (!self.hasElementInTableScope(tag_tk.name.toTag().?)) {
                                    self.parseError(.end_table_element_without_scope);
                                    return .PR_Done;
                                } else {
                                    self.closeCell();
                                    return try self.step_E(tk, null);
                                }
                            }
                        },
                    }
                },
                else => {},
            }

            // Anything else
            return try self.step_E(tk, .InBodyMode);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-intemplate
        .InTemplateMode => {
            switch (tk) {
                .CharacterToken, .CommentToken, .ProcessingInstructionToken, .DoctypeToken => {
                    return try self.step_E(tk, .InBodyMode);
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.oneOf(&.{ .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title })) {
                                return try self.step_E(tk, .InHeadMode);
                            } else if (tag_tk.name.oneOf(&.{ .caption, .colgroup, .tbody, .tfoot, .thead })) {
                                _ = self.temp_insert_modes.pop();
                                try self.temp_insert_modes.append(self.allocator, .InTableMode);
                                self.insert_mode = .InTableMode;
                                return try self.step_E(tk, null);
                            } else if (tag_tk.name.is(.col)) {
                                _ = self.temp_insert_modes.pop();
                                try self.temp_insert_modes.append(self.allocator, .InColumnGroupMode);
                                self.insert_mode = .InColumnGroupMode;
                                return try self.step_E(tk, null);
                            } else if (tag_tk.name.is(.tr)) {
                                _ = self.temp_insert_modes.pop();
                                try self.temp_insert_modes.append(self.allocator, .InTableBodyMode);
                                self.insert_mode = .InTableBodyMode;
                                return try self.step_E(tk, null);
                            } else if (tag_tk.name.oneOf(&.{ .td, .th })) {
                                _ = self.temp_insert_modes.pop();
                                try self.temp_insert_modes.append(self.allocator, .InRowMode);
                                self.insert_mode = .InRowMode;
                                return try self.step_E(tk, null);
                            } else {
                                _ = self.temp_insert_modes.pop();
                                try self.temp_insert_modes.append(self.allocator, .InBodyMode);
                                self.insert_mode = .InBodyMode;
                                return try self.step_E(tk, null);
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.template)) {
                                return try self.step_E(tk, .InHeadMode);
                            } else {
                                self.parseError(.invalid_tag_in_template);
                                return .PR_Done;
                            }
                        },
                    }
                },
                .EofToken => {
                    if (!self.hasElement(.template)) return .PR_StopParsing;
                    self.parseError(.eof_in_template);
                    self.popUntilPopped(.template);
                    self.clearActiveFormattingElementsToLastMarker();
                    _ = self.temp_insert_modes.pop();
                    self.resetInsertionModeAppropriately();
                    return try self.step_E(tk, null);
                },
                else => {},
            }
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-afterbody
        .AfterBodyMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => return try self.step_E(tk, .InBodyMode),
                    .NotWhitespace => break :sw,
                },
                .CommentToken => |cmt_tk| {
                    self.insertComment(cmt_tk, &.{ .last_child = self.open_elements.at(0).asNode() });
                    return .PR_Done;
                },
                .ProcessingInstructionToken => |pi_tk| {
                    self.insertProcessingInstruction(pi_tk, &.{ .last_child = self.open_elements.at(0).asNode() });
                    return .PR_Done;
                },
                .DoctypeToken => {
                    self.unexpect(tk, .AfterBodyMode);
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) return try self.step_E(tk, .InBodyMode);
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.html)) {
                                if (self.frameset_ok) {
                                    self.parseError(.end_html_with_frameset_ok);
                                    return .PR_Done;
                                }
                                self.insert_mode = .AfterAfterBodyMode;
                                return .PR_Done;
                            }
                        },
                    }
                },
                .EofToken => return .PR_StopParsing,
                else => {},
            }

            // Anything else
            self.unexpect(tk, .AfterBodyMode);
            self.insert_mode = .InBodyMode;
            return try self.step_E(tk, null);
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inframeset
        .InFramesetMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => {
                        try self.insertCharacter_E(null, tk);
                        return .PR_Done;
                    },
                    .NotWhitespace => break :sw,
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
                    self.unexpect(tk, .InFramesetMode);
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) {
                                return try self.step_E(tk, .InBodyMode);
                            } else if (tag_tk.name.is(.frameset)) {
                                _ = try self.insertHtmlElement_E(tag_tk);
                                return .PR_Done;
                            } else if (tag_tk.name.is(.frame)) {
                                _ = try self.insertHtmlElement_E(tag_tk);
                                _ = self.open_elements.pop();
                                return .PR_AckSelfClosing;
                            } else if (tag_tk.name.is(.noframes)) {
                                return try self.step_E(tk, .InHeadMode);
                            }
                        },
                        .EndTag => {
                            if (tag_tk.name.is(.frameset)) {
                                if (self.currentNode().local_name.is(.html)) {
                                    self.parseError(.end_frameset_with_html_current_node);
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
                    if (!self.currentNode().local_name.is(.html))
                        self.parseError(.eof_in_frameset);

                    return .PR_StopParsing;
                },
                else => {},
            }

            // Anything else
            self.unexpect(tk, .InFramesetMode);
            return .PR_Done;
        },

        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-afterframeset
        .AfterFramesetMode => {
            sw: switch (tk) {
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => {
                        try self.insertCharacter_E(null, tk);
                        return .PR_Done;
                    },
                    .NotWhitespace => break :sw,
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
                    self.unexpect(tk, .AfterFramesetMode);
                    return .PR_Done;
                },
                .TagToken => |tag_tk| {
                    switch (tag_tk.kind) {
                        .StartTag => {
                            if (tag_tk.name.is(.html)) {
                                return try self.step_E(tk, .InBodyMode);
                            } else if (tag_tk.name.is(.noframes)) {
                                return try self.step_E(tk, .InHeadMode);
                            }
                        },
                        .EndTag => {
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
            self.unexpect(tk, .AfterFramesetMode);
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
                    return try self.step_E(tk, .InBodyMode);
                },
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => return try self.step_E(tk, .InBodyMode),
                    .NotWhitespace => break :sw,
                },
                .TagToken => |tag_tk| {
                    if (tag_tk.kind == .StartTag and tag_tk.name.is(.html)) {
                        return try self.step_E(tk, .InBodyMode);
                    }
                },
                .EofToken => {
                    return .PR_StopParsing;
                },
                else => {},
            }

            // Anything else
            self.unexpect(tk, .AfterAfterBodyMode);
            self.insert_mode = .InBodyMode;
            return try self.step_E(tk, null);
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
                    return try self.step_E(tk, .InBodyMode);
                },
                .CharacterToken => |ch_tk| switch (ch_tk.split_status) {
                    .NotSplit => return .PR_SplitWhitespace,
                    .Whitespace => return try self.step_E(tk, .InBodyMode),
                    .NotWhitespace => break :sw,
                },
                .TagToken => |tag_tk| {
                    if (tag_tk.kind == .StartTag) {
                        if (tag_tk.name.is(.html)) {
                            return try self.step_E(tk, .InBodyMode);
                        } else if (tag_tk.name.is(.noframes)) {
                            return try self.step_E(tk, .InHeadMode);
                        }
                    }
                },
                .EofToken => return .PR_StopParsing,
                else => {},
            }

            // Anything else
            self.unexpect(tk, .AfterAfterFramesetMode);
            return .PR_Done;
        },
    }
    return .PR_Done;
}
