pub const parse = @import("properties/parse.zig");
pub const types = @import("properties/types.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
