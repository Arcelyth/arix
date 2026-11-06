pub const common = @import("url/common.zig");
pub const idna = @import("url/idna.zig");
pub const parsing = @import("url/parsing.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
