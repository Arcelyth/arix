const SpecifiedSize = @import("../specified/size.zig").Size;
const Context = @import("Context.zig");

/// As specified, with length value computed
pub const Size = union(enum) {
    auto,
    min_content,
    max_content,
    fit_content,
    stretch,
    length: f64,
    percentage: f64,

    pub fn fromSpecified(value: SpecifiedSize, context: *const Context) Size {
        return switch (value) {
            .auto => .auto,
            .min_content => .min_content,
            .max_content => .max_content,
            .fit_content => .fit_content,
            .stretch => .stretch,
            .length => |length| .{ .length = context.computeLength(length) },
            .percentage => |percentage| .{ .percentage = percentage },
        };
    }
};
