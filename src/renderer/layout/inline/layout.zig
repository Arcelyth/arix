const std = @import("std");
const InlineFormattingContext = @import("InlineFormattingContext.zig");
const Fragment = @import("../fragment/Fragment.zig");
const Options = @import("../Options.zig");

pub const Result = struct {
    height: f64 = 0,
    // Preserved empty lines affect margin collapsing even without text fragments.
    has_line: bool = false,
};

/// Horizontal, baseline-aligned inline text with the initial direction:ltr.
pub fn layout(
    allocator: std.mem.Allocator,
    context: *const InlineFormattingContext,
    parent: *Fragment,
    width: f64,
    options: Options,
) !Result {
    _ = allocator;
    _ = context;
    _ = parent;
    _ = width;
    _ = options;
    @panic("TODO");
}
