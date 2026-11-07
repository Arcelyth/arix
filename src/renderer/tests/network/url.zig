pub const common = @import("url/common.zig");
pub const idna = @import("url/idna.zig");
pub const parsing = @import("url/parsing.zig");
pub const percent_encoding = @import("url/percent_encoding.zig");
pub const toascii = @import("url/toascii.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
