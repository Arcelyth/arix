const Declaration = @import("../../css/properties/types.zig").Declaration;
const Specificity = @import("../../css/selectors/Specificity.zig");

// https://www.w3.org/TR/css-cascade-5/#cascading-origins
pub const Origin = enum {
    user_agent,
    user,
    author,
};

pub const MatchedRule = struct {
    /// Borrowed from the prepared stylesheet, in declaration order.
    declarations: []const Declaration,
    specificity: Specificity,
    origin: Origin,
};
