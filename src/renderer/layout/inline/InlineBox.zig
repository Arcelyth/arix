const InlineBox = @This();
const LayoutBoxBase = @import("../LayoutBoxBase.zig");

/// A non-atomic inline box participates in its containing IFC; it does not
/// establish a separate formatting context for its children.
/// https://www.w3.org/TR/css-display-3/#inline-box
base: LayoutBoxBase,
