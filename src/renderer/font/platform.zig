pub const backend = switch (@import("builtin").os.tag) {
    .macos => @import("platform/core_text.zig"),
    .windows => @import("platform/direct_write.zig"),
    else => @import("platform/unsupported.zig"),
};

test {
    @import("std").testing.refAllDecls(@This());
}
