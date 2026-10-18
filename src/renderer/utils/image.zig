pub const ppm = @import("image/ppm.zig");
pub const bmp = @import("image/bmp.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
