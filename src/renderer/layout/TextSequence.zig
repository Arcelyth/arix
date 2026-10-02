const TextSequence = @This();
const StyledNode = @import("../style/StyledNode.zig");

/// Inclusive range of contiguous sibling text nodes. The source styled tree
/// must outlive the layout tree.
first: *const StyledNode,
last: *const StyledNode,
