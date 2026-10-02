const SpecifiedSize = @import("../specified/size.zig").Size;
const Context = @import("Context.zig");
const LengthPercentage = @import("length_percentage.zig").LengthPercentage;

/// As specified, with length value computed.
pub const Size = union(enum) {
    auto,
    min_content,
    max_content,
    fit_content,
    stretch,
    length_percentage: LengthPercentage,

    pub fn fromSpecified(value: SpecifiedSize, context: *const Context) Size {
        return switch (value) {
            .auto => .auto,
            .min_content => .min_content,
            .max_content => .max_content,
            .fit_content => .fit_content,
            .stretch => .stretch,
            .length_percentage => |numeric| .{ .length_percentage = LengthPercentage.fromSpecified(numeric, context) },
        };
    }

    pub fn resolve(size: Size, basis: ?f64) ?f64 {
        return switch (size) {
            .auto => null,
            .length_percentage => |value| switch (value) {
                .length => |length| length,
                .percentage => value.resolve(basis orelse return null),
            },
            else => @panic("TODO: intrinsic and stretch sizing"),
        };
    }
};
