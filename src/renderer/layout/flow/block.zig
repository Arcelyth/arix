const std = @import("std");
const BlockFormattingContext = @import("../flow.zig").BlockFormattingContext;
const LayoutBox = @import("../LayoutBox.zig");
const LayoutBoxBase = @import("../LayoutBoxBase.zig");
const Fragment = @import("../fragment.zig").Fragment;
const FragmentTree = @import("../fragment.zig").FragmentTree;
const ComputedValues = @import("../../css/properties/registry.zig").ComputedValues;
const Size = @import("../../css/values/computed/size.zig").Size;

pub const ContainingBlock = struct {
    width: f64,
    /// Null means the content height is indefinite, not zero.
    height: ?f64,
};

/// https://www.w3.org/TR/CSS2/box.html#collapsing-margins
pub const CollapsedMargin = struct {
    positive: f64 = 0,
    negative: f64 = 0,

    fn init(margin: f64) CollapsedMargin {
        return .{ .positive = @max(0, margin), .negative = @min(0, margin) };
    }

    fn adjoin(self: *CollapsedMargin, other: CollapsedMargin) void {
        self.positive = @max(self.positive, other.positive);
        self.negative = @min(self.negative, other.negative);
    }

    fn value(self: CollapsedMargin) f64 {
        return self.positive + self.negative;
    }
};

pub const BlockResult = struct {
    /// Generated geometry.
    fragment: *Fragment,
    /// Margin-collapse information needed for parent and sibling placement.
    start: CollapsedMargin,
    end: CollapsedMargin,
    /// Whether the block’s top and bottom margins collapse through it
    through: bool,
    /// border-box height used to advance the parent’s placement cursor
    border_height: f64,
};

pub fn layout(allocator: std.mem.Allocator, context: *const BlockFormattingContext, viewport_width: f64, viewport_height: f64) !FragmentTree {
    var result: FragmentTree = .{
        .initial_containing_block = .{
            .x = 0,
            .y = 0,
            .width = viewport_width,
            .height = viewport_height,
        },
    };
    const box = switch (context.contents) {
        .block_level_boxes => |first| first orelse return result,
        .inline_formatting_context => @panic("TODO: inline layout"),
    };
    const root = try layoutBlock(allocator, box, .{
        .width = viewport_width,
        .height = viewport_height,
    });

    root.fragment.content.box.base.rect.y = root.start.value() + root.fragment.content.box.padding.top;
    result.root = root.fragment;
    return result;
}

fn layoutBlock(allocator: std.mem.Allocator, box: *const LayoutBox, containing: ContainingBlock) !BlockResult {
    const block = switch (box.content) {
        .block_level => |*block| block,
        else => @panic("TODO: inline layout"),
    };
    const container = switch (block.*) {
        .independent => |*context| &context.contents.flow.contents,
        .same_formatting_context => |*normal| &normal.contents,
    };
    const first = switch (container.*) {
        .block_level_boxes => |first| first,
        .inline_formatting_context => @panic("TODO: inline layout"),
    };
    const independent = block.* == .independent;
    const height = block.base().style.values.height.resolve(containing.height);

    const fragment = try createBlockFragment(allocator, block.base(), containing);
    errdefer fragment.destroy(allocator);

    const children = try layoutChildren(allocator, fragment, first, .{
        .width = fragment.content.box.base.rect.width,
        .height = height,
    }, !independent and fragment.content.box.padding.top == 0);
    return finishBlock(fragment, independent, height, children);
}

fn createBlockFragment(allocator: std.mem.Allocator, base: *const LayoutBoxBase, containing: ContainingBlock) !*Fragment {
    _ = allocator;
    _ = base;
    _ = containing;
    @panic("TODO");
}

const ChildLayout = struct {
    start: CollapsedMargin = .{},
    pending: CollapsedMargin = .{},
    cursor: f64 = 0,
    at_start: bool = true,
};

/// Lay out each child in the parent's content box, then place it in normal flow.
fn layoutChildren(allocator: std.mem.Allocator, fragment: *Fragment, first: ?*LayoutBox, containing: ContainingBlock, collapse_start: bool) !ChildLayout {
    _ = allocator;
    _ = fragment;
    _ = first;
    _ = containing;
    _ = collapse_start;
    @panic("TODO");
}

fn finishBlock(fragment: *Fragment, independent: bool, height: ?f64, children: ChildLayout) BlockResult {
    _ = fragment;
    _ = independent;
    _ = height;
    _ = children;
    @panic("TODO");
}
