const selectors = @import("css/selectors.zig");
const syntax = @import("css/syntax.zig");
const namespace = @import("css/namespace.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
