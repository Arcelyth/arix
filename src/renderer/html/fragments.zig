const std = @import("std");
const strale = @import("strale");
const BufferDeque = strale.BufferDeque;
const DocumentFragment = @import("../dom/DocumentFragment.zig");
const Element = @import("../dom/Element.zig");
const Node = @import("../dom/Node.zig");
const ScriptingMode = @import("tree_builder/types.zig").ScriptingMode;
const LocalName = @import("local_name").LocalName;
const Tokenizer = @import("tokenizer/Tokenizer.zig");
const TokenizerOpts = Tokenizer.TokenizerOpts;
const token = @import("tokenizer/token.zig");
const Parser = @import("Parser.zig");
const ParserOpts = Parser.ParserOpts;
const TreeBuilder = @import("tree_builder/TreeBuilder.zig");
const TreeBuilderOpts = TreeBuilder.TreeBuilderOpts;

pub const FragmentTarget = union(enum) {
    element: *Element,
    document_fragment: *DocumentFragment,

    fn context(self: FragmentTarget) !*Element {
        return switch (self) {
            .element => |element| element,
            .document_fragment => |fragment| fragment.host orelse error.FragmentTargetHasNoHost,
        };
    }

    fn node(self: FragmentTarget) *Node {
        return switch (self) {
            .element => |element| element.asNode(),
            .document_fragment => |fragment| &fragment.node,
        };
    }

    fn customElementRegistry(self: FragmentTarget) ?*@import("../dom/CustomElementRegistry.zig") {
        return switch (self) {
            .element => |element| Element.lookingUpCustomElementRegistry(element.asNode()),
            .document_fragment => |fragment| blk: {
                const host = fragment.host orelse break :blk null;
                const shadow = host.shadow_root orelse break :blk null;
                break :blk if (&shadow.doc_frag == fragment) shadow.custom_element_registry else null;
            },
        };
    }
};

pub const FragmentOpts = struct {
    allow_declarative_shadow_roots: bool = false,
    scripting_mode: ScriptingMode = .Inert,
};

pub fn parseFragment(
    alloc: std.mem.Allocator,
    target: FragmentTarget,
    input: []const u8,
    opts: FragmentOpts,
) !*DocumentFragment {
    std.debug.assert(opts.scripting_mode == .Inert or opts.scripting_mode == .Fragment);
    const context = try target.context();

    const context_document = context.asNode().node_doc;
    const scripting_mode: ScriptingMode = if (context_document.scripting_enabled)
        opts.scripting_mode
    else
        .Disabled;
    const tk_opts: TokenizerOpts = .{};
    const tree_opts: TreeBuilderOpts = .{ .fragment_case = true, .allow_decl_shadow_roots = opts.allow_declarative_shadow_roots, .scripting_mode = scripting_mode };
    const parser_opts = ParserOpts{
        .tokenizer = tk_opts,
        .tree_builder = tree_opts,
    };
    const parser = try Parser.create(alloc, parser_opts);
    defer parser.destroy();

    parser.tree_builder.setDocumentType(.DT_Html);
    parser.tree_builder.document.mode = context_document.mode;
    parser.tree_builder.context = context;
    parser.tokenizer.state = parser.tree_builder.tokenizerStateForContextElement(scripting_mode);

    const root = Element.create(
        parser.tree_builder.document,
        LocalName.fromTag(.html),
        .NS_Html,
        null,
        null,
        false,
        target.customElementRegistry(),
    );
    parser.tree_builder.document.asNode().appendChild(root.asNode());
    try parser.tree_builder.open_elements.append(root);

    const fragment = try context_document.allocator.create(DocumentFragment);
    errdefer context_document.allocator.destroy(fragment);
    fragment.* = DocumentFragment.init(context_document);
    errdefer fragment.node.destroy(context_document.allocator);
    parser.tree_builder.root_insertion_target = fragment;

    if (context.ns == .NS_Html and context.local_name.is(.template))
        try parser.tree_builder.temp_insert_modes.append(alloc, .InTemplateMode);

    var attrs: std.ArrayList(token.Attribute) = .empty;
    errdefer {
        for (attrs.items) |*attr| attr.deinit();
        attrs.deinit(alloc);
    }
    try attrs.ensureTotalCapacity(alloc, context.attrs.data.items.len);
    for (context.attrs.data.items) |attr| attrs.appendAssumeCapacity(.{
        .name = attr.local_name.clone(),
        .value = attr.value.clone(),
        .namespace = attr.ns,
        .prefix = if (attr.prefix) |prefix| prefix.clone() else null,
    });
    parser.tree_builder.context_start_tag = .{ .TagToken = .{
        .kind = .StartTag,
        .name = context.local_name.clone(),
        .self_closing = false,
        .attrs = attrs,
    } };

    parser.tree_builder.resetInsertionModeAppropriately();

    var ancestor: ?*Node = context.asNode();
    while (ancestor) |node| : (ancestor = node.parent) {
        if (node.type_id != .DOM_Element) continue;
        const element = node.downcast(Element);
        if (element.ns == .NS_Html and element.local_name.is(.form)) {
            parser.tree_builder.form_el_ptr = element;
            break;
        }
    }

    var stream = try BufferDeque(.utf8, .not_atomic, true).init(alloc);
    defer stream.deinit();
    try stream.pushBackSlice(input);
    try parser.tokenizer.step_E(&stream);
    return fragment;
}
