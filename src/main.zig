const std = @import("std");

pub fn main() !void {
    std.debug.print("hello world\n", .{});
}


test {
    _ = @import("renderer.zig");
    _ = @import("utils.zig");
}
