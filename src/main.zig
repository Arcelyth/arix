const std = @import("std");

comptime {
    _ = @import("renderer/html/encoding/attr.zig");
    _ = @import("renderer/html/encoding/sniff.zig");
    _ = @import("renderer/html/encoding/encoding.zig");
}

pub fn main() !void {
    std.debug.print("hello world\n", .{});
}
