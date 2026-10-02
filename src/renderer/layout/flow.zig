const std = @import("std");
const LayoutBox = @import("LayoutBox.zig");
const LayoutBoxBase = @import("LayoutBoxBase.zig");
const inline_ = @import("inline.zig");
const InlineFormattingContext = inline_.InlineFormattingContext;
const IndependentFormattingContext = @import("formatting_context.zig").IndependentFormattingContext;

pub const BlockFormattingContext = struct {
    contents: BlockContainer = .{ .block_level_boxes = null },

    pub fn deinit(self: *BlockFormattingContext, allocator: std.mem.Allocator) void {
        self.contents.deinit(allocator);
    }
};

/// https://www.w3.org/TR/css-display-3/#block-container
pub const BlockContainer = union(enum) {
    block_level_boxes: ?*LayoutBox,
    /// Inline formatting contexts exist within (are part of their containing) block formatting contexts
    inline_formatting_context: InlineFormattingContext,

    /// Tree entries are destroyed by LayoutBox; release only context-local data.
    pub fn deinit(self: *BlockContainer, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .block_level_boxes => {},
            .inline_formatting_context => |*context| context.root.base.deinit(allocator),
        }
    }
};

/// An ordinary block container continues its surrounding BFC rather than
/// establishing an independent one. Its inline contents can still form an IFC.
pub const SameFormattingContextBlock = struct {
    base: LayoutBoxBase,
    contents: BlockContainer = .{ .block_level_boxes = null },
};

pub const BlockLevelBox = union(enum) {
    independent: IndependentFormattingContext,
    same_formatting_context: SameFormattingContextBlock,

    pub fn base(self: *const BlockLevelBox) *const LayoutBoxBase {
        return switch (self.*) {
            .independent => |*context| &context.base,
            .same_formatting_context => |*block| &block.base,
        };
    }

    pub fn container(self: *BlockLevelBox) *BlockContainer {
        return switch (self.*) {
            .independent => |*context| &context.contents.flow.contents,
            .same_formatting_context => |*block| &block.contents,
        };
    }

    pub fn deinit(self: *BlockLevelBox, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .independent => |*context| context.deinit(allocator),
            .same_formatting_context => |*block| {
                block.contents.deinit(allocator);
                block.base.deinit(allocator);
            },
        }
    }
};
