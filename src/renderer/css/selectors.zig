pub const Parser = @import("selectors/Parser.zig");
pub const Specificity = @import("selectors/Specificity.zig");
pub const parse = @import("selectors/parse.zig");
pub const matching = @import("selectors/matching.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
