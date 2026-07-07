pub const attr = @import("attr.zig");
pub const encoding = @import("encoding.zig");
pub const sniff = @import("sniff.zig");

test {
    @import("std").testing.refAllDecls(@This());
}

comptime {
    _ = @import("attr_test.zig");
    _ = @import("sniff_test.zig");
}
