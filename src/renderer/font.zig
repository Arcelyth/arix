pub const platform = @import("font/platform.zig");
pub const Matcher = @import("font/Matcher.zig");
pub const matching = @import("font/matching.zig");
pub const opentype = @import("font/opentype.zig");
pub const Metrics = @import("font/Metrics.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
