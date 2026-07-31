const std = @import("std");
const config = @import("config");

pub fn main() !void {
    std.debug.print("hello world\n", .{});
}

test {
    _ = @import("renderer.zig");
    _ = @import("utils.zig");
    _ = @import("dom.zig");
}
