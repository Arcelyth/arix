pub const BoxFragment = @import("fragment/BoxFragment.zig");
pub const BaseFragment = @import("fragment/BaseFragment.zig");

pub const Fragment = union(enum) {
    box: BoxFragment,
};

test {
    @import("std").testing.refAllDecls(@This());
}
