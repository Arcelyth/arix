pub const display = @import("paint/display.zig");
pub const Canvas = @import("paint/Canvas.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
