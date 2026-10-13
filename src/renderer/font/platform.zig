pub const backend = switch (@import("builtin").os.tag) {
    .macos => @import("platform/core_text.zig"),
    else => @import("platform/unsupported.zig"),
};

test {
    @import("std").testing.refAllDecls(@This());
}
