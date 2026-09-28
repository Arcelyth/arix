const std = @import("std");

pub inline fn assert(result: bool) void {
    std.debug.assert(result);
}

pub inline fn assertWithMessage(result: bool, message: []const u8) void {
    if (!result) @panic(message);
}
