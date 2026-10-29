const std = @import("std");
const config = @import("config");
pub const renderer = @import("renderer.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
