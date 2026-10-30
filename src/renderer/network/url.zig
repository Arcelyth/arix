pub const host = @import("url/host.zig");
pub const Input = @import("url/Input.zig");
pub const Parser = @import("url/Parser.zig");
pub const Url = @import("url/Url.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
