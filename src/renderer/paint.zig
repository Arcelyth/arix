pub const Painter = @import("paint/Painter.zig");
pub const display = @import("paint/display.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
