const Context = @import("Context.zig");
const SpecifiedLineHeight = @import("../specified.zig").LineHeight;
const LengthPercentage = @import("length_percentage.zig").LengthPercentage;

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
