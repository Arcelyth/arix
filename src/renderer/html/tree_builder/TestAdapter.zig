/// A simple adapter for testing.
const TestAdapter = @This();

const std = @import("std");
const Vtable = @import("TreeAdapter.zig").VTable;
const TreeAdapter = @import("TreeAdapter.zig");
const e = @import("error.zig");
const TreeBuilderError = e.TreeBuilderError;
const testing = std.testing;

const vtable = Vtable{
    .handleErrorFn = handleError,
};

allocator: std.mem.Allocator,

pub fn init(alloc: std.mem.Allocator) TestAdapter {
    return .{
        .allocator = alloc,
    };
}

pub fn adapter(self: *TestAdapter) TreeAdapter {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

pub fn deinit(self: *TestAdapter) void {
    _ = self;
}

// Implement TreeAdapter's method.
pub fn handleError(ptr: *anyopaque, err: TreeBuilderError) void {
    const self: *TestAdapter = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = err;
}
