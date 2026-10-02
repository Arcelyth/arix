const InlineFormattingContext = @This();

const InlineBox = @import("InlineBox.zig");
const LayoutBox = @import("../LayoutBox.zig");
const LayoutBoxBase = @import("../LayoutBoxBase.zig");
const ComputedStyle = @import("../../style/computed/ComputedStyle.zig");

/// https://www.w3.org/TR/css-inline-3/#root-inline-box
root: InlineBox,
items: *LayoutBox,
