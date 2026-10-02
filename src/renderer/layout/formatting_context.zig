const std = @import("std");
const LayoutBoxBase = @import("LayoutBoxBase.zig");
const BlockFormattingContext = @import("flow.zig").BlockFormattingContext;

/// https://www.w3.org/TR/css-display-3/#independent-formatting-context
pub const IndependentFormattingContext = struct {
    base: LayoutBoxBase,
    contents: union(enum) {
        flow: BlockFormattingContext,
    } = .{ .flow = .{} },

    pub fn deinit(self: *IndependentFormattingContext, allocator: std.mem.Allocator) void {
        self.contents.flow.deinit(allocator);
        self.base.deinit(allocator);
    }
};
