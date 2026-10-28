pub const host = @import("url/host.zig");
pub const Url = @import("url/Url.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
