pub const ppm = @import("image/ppm.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
