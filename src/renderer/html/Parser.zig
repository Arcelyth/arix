const Parser = @This();

const std = @import("std");
const strale = @import("strale");
const BufferDeque = strale.BufferDeque;
const DocumentFragment = @import("../dom/DocumentFragment.zig");
const Element = @import("../dom/Element.zig");
const Node = @import("../dom/Node.zig");
const LocalName = @import("local_name").LocalName;
const Tokenizer = @import("tokenizer/Tokenizer.zig");
const token = @import("tokenizer/token.zig");
const TokenizerState = @import("tokenizer/state.zig").TokenizerState;
const TreeAdapter = @import("tree_builder/TreeAdapter.zig");
const TreeBuilder = @import("tree_builder/TreeBuilder.zig");
const TreeBuilderError = @import("tree_builder/error.zig").TreeBuilderError;
const ScriptingMode = @import("tree_builder/types.zig").ScriptingMode;

const vtable = TreeAdapter.VTable{
    .handleErrorFn = handleError,
};

pub const ParserOpts = struct {
    tokenizer: Tokenizer.TokenizerOpts,
    tree_builder: TreeBuilder.TreeBuilderOpts,
};

allocator: std.mem.Allocator,
errors: std.ArrayList(TreeBuilderError),
tokenizer: Tokenizer,
tree_builder: TreeBuilder,

pub fn create(alloc: std.mem.Allocator, opts: ParserOpts) !*Parser {
    const self = try alloc.create(Parser);
    self.allocator = alloc;
    self.errors = .empty;
    self.tree_builder = TreeBuilder.init(alloc, self.adapter(), opts.tree_builder);
    self.tokenizer = Tokenizer.init(alloc, self.tree_builder.adapter(), opts.tokenizer);
    return self;
}

pub fn destroy(self: *Parser) void {
    const alloc = self.allocator;
    self.errors.deinit(self.allocator);
    self.tokenizer.deinit();
    self.tree_builder.deinit();
    alloc.destroy(self);
}

// --- Implement TreeAdapter ---

pub fn adapter(self: *Parser) TreeAdapter {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

pub fn handleError(ptr: *anyopaque, err: TreeBuilderError) void {
    const self: *Parser = @ptrCast(@alignCast(ptr));
    self.errors.append(self.allocator, err) catch unreachable;
}
