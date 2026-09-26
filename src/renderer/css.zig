pub const selectors = @import("css/selectors.zig");
pub const syntax = @import("css/syntax.zig");
pub const namespace = @import("css/namespace.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
