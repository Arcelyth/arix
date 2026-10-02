const TextSequence = @This();
const StyledNode = @import("../style/StyledNode.zig");
const Text = @import("../dom/Text.zig");
const ascii = @import("../utils/ascii.zig");

/// Inclusive range of contiguous sibling text nodes. The source styled tree
/// must outlive the layout tree.
first: *const StyledNode,
last: *const StyledNode,

/// https://www.w3.org/TR/css-text-3/#white-space-processing
pub fn isWhitespace(self: TextSequence) bool {
    var current = self.first;
    while (true) {
        for (current.node.downcast(Text).data.slice()) |byte| {
            if (!ascii.isCssWhitespace(byte)) return false;
        }
        if (current == self.last) return true;
        current = current.next_sibling().?;
    }
}
