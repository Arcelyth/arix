const BoxTree = @This();

const std = @import("std");
const BlockFormattingContext = @import("flow.zig").BlockFormattingContext;

/// The initial containing block's BFC. Contains the document element's
/// principal box, or no box when the document element has display:none.
root: BlockFormattingContext = .{},
