const SpecifiedMargin = @import("../specified/margin.zig").Margin;
const Context = @import("Context.zig");
const LengthPercentage = @import("length_percentage.zig").LengthPercentage;

pub const Margin = union(enum) {
    auto,
    length_percentage: LengthPercentage,

    pub fn initial(_: *const Context) Margin {
        return .{ .length_percentage = .{ .length = 0 } };
    }

    pub fn fromSpecified(value: SpecifiedMargin, context: *const Context) Margin {
        return switch (value) {
            .auto => .auto,
            .length_percentage => |length| .{ .length_percentage = LengthPercentage.fromSpecified(length, context) },
        };
    }

    pub fn resolve(self: Margin, containing_logical_width: f64) ?f64 {
        return switch (self) {
            .auto => null,
            .length_percentage => |length| length.resolve(containing_logical_width),
        };
    }
};
