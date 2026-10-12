pub const backend = switch (@import("builtin").os.tag) {
    .macos => @import("platform/core_text.zig"),
    else => @panic("TODO"),
};

test {
    @import("std").testing.refAllDecls(@This());
}
