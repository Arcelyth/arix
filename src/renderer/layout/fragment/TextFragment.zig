const std = @import("std");
const BaseFragment = @import("BaseFragment.zig");
const ComputedStyle = @import("../../style/computed/ComputedStyle.zig");
const ShapedText = @import("../../font/ShapedText.zig");
const Metrics = @import("../../font/Metrics.zig");

base: BaseFragment,
font_metrics: Metrics,
style: ComputedStyle,
/// Owned text after whitespace processing. Glyph clusters index these bytes.
text: []u8,
run: ShapedText.Run,

pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
    self.run.deinit(allocator);
    allocator.free(self.text);
}
