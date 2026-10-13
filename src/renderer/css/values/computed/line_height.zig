const Context = @import("Context.zig");
const SpecifiedLineHeight = @import("../specified.zig").LineHeight;
const LengthPercentage = @import("length_percentage.zig").LengthPercentage;
const Metrics = @import("../../../font/Metrics.zig");

/// Compute percentages to lengths.
pub const LineHeight = union(enum) { normal, number: f64, length: f64 };

pub fn fromSpecified(value: SpecifiedLineHeight, context: *const Context) LineHeight {
    return switch (value) {
        .normal => .normal,
        .number => |number| .{ .number = number },
        .length_percentage => |size| .{
            .length = LengthPercentage.fromSpecified(size, context).resolve(context.font_size),
        },
    };
}

/// The vertical extents of a line box relative to its baseline.
pub const Extents = struct {
    above: f64,
    below: f64,

    /// Expands the extents to include another set of vertical extents.
    pub fn include(self: *Extents, other: Extents) void {
        self.above = @max(self.above, other.above);
        self.below = @max(self.below, other.below);
    }

    pub fn height(self: Extents) f64 {
        return self.above + self.below;
    }
};

pub fn resolve(value: LineHeight, size: f64, metrics: Metrics) Extents {
    const height = switch (value) {
        .normal => metrics.ascent + metrics.descent + metrics.leading,
        .number => |number| number * size,
        .length => |length| length,
    };
    const half_leading = (height - metrics.ascent - metrics.descent) / 2;
    return .{
        .above = metrics.ascent + half_leading,
        .below = metrics.descent + half_leading,
    };
}
