pub const atom_test = @import("renderer/dom/atom_name_test.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
