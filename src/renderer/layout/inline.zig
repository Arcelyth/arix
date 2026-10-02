pub const InlineBox = @import("inline/InlineBox.zig");
pub const InlineFormattingContext = @import("inline/InlineFormattingContext.zig");

const std = @import("std");
const IndependentFormattingContext = @import("formatting_context.zig").IndependentFormattingContext;
const LayoutBoxBase = @import("LayoutBoxBase.zig");

/// Inline flow participates in the surrounding IFC. Atomic inline-level
/// boxes instead establish an independent context for their own contents.
/// https://www.w3.org/TR/css-display-3/#atomic-inline
pub const InlineLevelBox = union(enum) {
    inline_box: InlineBox,
    atomic: IndependentFormattingContext,

    pub fn base(self: *const InlineLevelBox) *const LayoutBoxBase {
        return switch (self.*) {
            .inline_box => |*box| &box.base,
            .atomic => |*context| &context.base,
        };
    }

    pub fn deinit(self: *InlineLevelBox, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .inline_box => |*box| box.base.deinit(allocator),
            .atomic => |*context| context.deinit(allocator),
        }
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
