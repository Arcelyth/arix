pub const display = @import("paint/display.zig");
pub const Canvas = @import("paint/Canvas.zig");
pub const text = @import("paint/text.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
