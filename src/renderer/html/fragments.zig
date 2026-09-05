const std = @import("std");
const Vtable = @import("tree_builder/TreeAdapter.zig").VTable;
const e = @import("tree_builder/error.zig");
const TreeBuilderError = e.TreeBuilderError;
const testing = std.testing;
const DocumentFragment = @import("../dom/DocumentFragment.zig");
const Element = @import("../dom/Element.zig");
const Node = @import("../dom/Node.zig");
const ScriptingMode = @import("tree_builder/types.zig").ScriptingMode;
const LocalName = @import("local_name").LocalName;
const Tokenizer = @import("tokenizer/Tokenizer.zig");
const TokenizerOpts = Tokenizer.TokenizerOpts;
const token = @import("tokenizer/token.zig");
const TokenizerState = @import("tokenizer/state.zig").TokenizerState;
const Parser = @import("Parser.zig");
const ParserOpts = Parser.ParserOpts;
const TreeAdapter = @import("tree_builder/TreeAdapter.zig");
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

    const tk_opts: TokenizerOpts = .{};
    const tree_opts: TreeBuilderOpts = .{};
    const parser_opts = ParserOpts{
        .tokenizer = tk_opts,
        .tree_builder = tree_opts,
    };
    const parser = try Parser.create(alloc, parser_opts);
    defer parser.destroy();

    parser.tree_builder.setDocumentType(.DT_Html);
    const context_document = context.asNode().node_doc;
    _ = context_document;
    _ = input;
    @panic("TODO");
}
