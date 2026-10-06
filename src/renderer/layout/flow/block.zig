const std = @import("std");
const BlockFormattingContext = @import("../flow.zig").BlockFormattingContext;
const LayoutBox = @import("../LayoutBox.zig");
const LayoutBoxBase = @import("../LayoutBoxBase.zig");
const Fragment = @import("../fragment.zig").Fragment;
const FragmentTree = @import("../fragment.zig").FragmentTree;
const ComputedValues = @import("../../css/properties/registry.zig").ComputedValues;
const EdgeSizes = @import("../../geometry/EdgeSizes.zig");
const Size = @import("../../css/values/computed/size.zig").Size;
const line_width = @import("../../css/values/computed/line_width.zig");
const PropertyId = @import("../../css/properties/registry.zig").PropertyId;

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

pub fn layout(
    allocator: std.mem.Allocator,
    context: *const BlockFormattingContext,
    viewport_width: f64,
    viewport_height: f64,
) !FragmentTree {
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

    root.fragment.content.box.base.rect.y = root.start.value() + root.fragment.content.box.border.top + root.fragment.content.box.padding.top;
    result.root = root.fragment;
    return result;
}

fn layoutBlock(
    allocator: std.mem.Allocator,
    box: *const LayoutBox,
    containing: ContainingBlock,
) std.mem.Allocator.Error!BlockResult {
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
    }, !independent and fragment.content.box.padding.top == 0 and fragment.content.box.border.top == 0);

    return finishBlock(fragment, independent, height, children);
}

fn createBlockFragment(
    allocator: std.mem.Allocator,
    base: *const LayoutBoxBase,
    containing: ContainingBlock,
) !*Fragment {
    const style = &base.style.values;
    const border = borderWidths(style);
    const padding: EdgeSizes = .{
        .top = style.padding_top.resolve(containing.width),
        .right = style.padding_right.resolve(containing.width),
        .bottom = style.padding_bottom.resolve(containing.width),
        .left = style.padding_left.resolve(containing.width),
    };
    const horizontal = usedWidth(
        style,
        containing.width,
        padding.left + padding.right + border.left + border.right,
    );

    const fragment = try allocator.create(Fragment);
    fragment.* = Fragment.init(.{ .box = .{
        .base = .{
            .rect = .{
                .x = horizontal.left + border.left + padding.left,
                .y = 0,
                .width = horizontal.width,
                .height = 0,
            },
        },
        .source = base.source,
        .style = base.style,
        .padding = padding,
        .border = border,
        .margin = .{
            .top = style.margin_top.resolve(containing.width) orelse 0,
            .right = horizontal.right,
            .bottom = style.margin_bottom.resolve(containing.width) orelse 0,
            .left = horizontal.left,
        },
    } });
    return fragment;
}

fn borderWidths(style: *const ComputedValues) EdgeSizes {
    var widths: EdgeSizes = .{};
    inline for (.{ "top", "right", "bottom", "left" }) |side| {
        const property = "border_" ++ side ++ "_width";
        @field(widths, side) = line_width.toResolvedValue(@field(style, property), &.{
            .style = style,
            .current_longhand = @field(PropertyId, property),
        });
    }
    return widths;
}

const ChildLayout = struct {
    start: CollapsedMargin = .{},
    pending: CollapsedMargin = .{},
    cursor: f64 = 0,
    at_start: bool = true,
};

/// Lay out each child in the parent's content box, then place it in normal flow.
fn layoutChildren(
    allocator: std.mem.Allocator,
    fragment: *Fragment,
    first: ?*LayoutBox,
    containing: ContainingBlock,
    collapse_start: bool,
) !ChildLayout {
    var result: ChildLayout = .{};
    var child = first;
    while (child) |current| : (child = current.next_sibling()) {
        const placed = try layoutBlock(allocator, current, containing);
        fragment.appendChild(placed.fragment);
        placeChild(&result, placed, collapse_start);
    }
    if (result.at_start and collapse_start) result.start.adjoin(result.pending);
    return result;
}

fn placeChild(state: *ChildLayout, child: BlockResult, collapse_start: bool) void {
    state.pending.adjoin(child.start);
    const border_top = if (state.at_start and collapse_start)
        state.cursor
    else
        state.cursor + state.pending.value();

    child.fragment.content.box.base.rect.y = border_top + child.fragment.content.box.border.top + child.fragment.content.box.padding.top;
    if (child.through) {
        state.pending.adjoin(child.end);
    } else {
        if (state.at_start and collapse_start)
            state.start.adjoin(state.pending);

        state.cursor = border_top + child.border_height;
        state.pending = child.end;
        state.at_start = false;
    }
}

/// Resolve auto height and return the margins that adjoining boxes can collapse.
fn finishBlock(
    fragment: *Fragment,
    independent: bool,
    height: ?f64,
    children: ChildLayout,
) BlockResult {
    const padding = fragment.content.box.padding;
    const border = fragment.content.box.border;
    var start = CollapsedMargin.init(fragment.content.box.margin.top);
    start.adjoin(children.start);

    var end = CollapsedMargin.init(fragment.content.box.margin.bottom);
    const collapse_start = !independent and padding.top == 0 and border.top == 0;
    const collapse_end = !independent and padding.bottom == 0 and border.bottom == 0 and height == null;
    const through = !independent and padding.top == 0 and padding.bottom == 0 and border.top == 0 and border.bottom == 0 and
        (height == null or height.? == 0) and children.at_start;

    var cursor = children.cursor;
    if (through)
        // `start` only keeps the margin needed to determine the block's position;
        // `end` keeps the full collapsed margin for the next sibling.
        end.adjoin(start)
    else if (collapse_end)
        end.adjoin(children.pending)
    else if (!(children.at_start and collapse_start))
        cursor += children.pending.value();

    const content_height = height orelse @max(0, cursor);
    fragment.content.box.base.rect.height = content_height;
    return .{
        .fragment = fragment,
        .start = start,
        .end = end,
        .through = through,
        .border_height = border.top + padding.top + content_height + padding.bottom + border.bottom,
    };
}

const Horizontal = struct {
    width: f64,
    left: f64,
    right: f64,
};

/// Solve the width constraint. With the initial direction:ltr, over-constraint
/// changes the used right margin, not the computed value.
/// https://www.w3.org/TR/CSS2/visudet.html#blockwidth
fn usedWidth(style: *const ComputedValues, containing_width: f64, edges: f64) Horizontal {
    const left = style.margin_left.resolve(containing_width);
    const right = style.margin_right.resolve(containing_width);
    var result: Horizontal = .{
        .width = style.width.resolve(containing_width) orelse @max(0, containing_width - edges - (left orelse 0) - (right orelse 0)),
        .left = left orelse 0,
        .right = right orelse 0,
    };

    const remaining = containing_width - edges - result.width - result.left - result.right;
    if (style.width == .auto or remaining < 0) {
        result.right += remaining;
    } else if (left == null and right == null) {
        result.left = remaining / 2;
        result.right = result.left;
    } else if (left == null) {
        result.left = remaining;
    } else {
        result.right += remaining;
    }

    return result;
}
