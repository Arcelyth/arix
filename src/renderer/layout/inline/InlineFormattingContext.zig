/// https://www.w3.org/TR/css-inline-3/#root-inline-box
const InlineFormattingContext = @This();

const InlineBox = @import("InlineBox.zig");
const LayoutBox = @import("../LayoutBox.zig");
const LayoutBoxBase = @import("../LayoutBoxBase.zig");
const ComputedStyle = @import("../../style/computed/ComputedStyle.zig");

root: InlineBox,
items: *LayoutBox,

pub fn init(parent_style: *const ComputedStyle, items: *LayoutBox) InlineFormattingContext {
    return .{
        .root = .{ .base = LayoutBoxBase.anonymous(parent_style, .{}) },
        .items = items,
    };
}
