pub const host = @import("url/host.zig");
pub const Input = @import("url/Input.zig");
pub const Parser = @import("url/Parser.zig");
pub const Url = @import("url/Url.zig");
pub const path = @import("url/path.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
