const Specified = @import("../specified/length_percentage.zig").LengthPercentage;
const Context = @import("Context.zig");

pub const LengthPercentage = union(enum) {
    length: f64,
    percentage: f64,

    pub fn fromSpecified(value: Specified, context: *const Context) LengthPercentage {
        return switch (value) {
            .length => |length| .{ .length = context.computeLength(length) },
            .percentage => |percentage| .{ .percentage = percentage },
        };
    }

    /// Converts a computed length-percentage into a pixel value.
    pub fn resolve(self: LengthPercentage, value: f64) f64 {
        return switch (self) {
            .length => |length| length,
            .percentage => |percentage| value * (percentage / 100),
        };
    }
};
