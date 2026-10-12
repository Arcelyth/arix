pub const platform = @import("font/platform.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
