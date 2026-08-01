pub const local_name_test = @import("renderer/dom/local_name_test.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
