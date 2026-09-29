pub const parse = @import("properties/parse.zig");
pub const types = @import("properties/types.zig");
pub const registry = @import("properties/registry.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
