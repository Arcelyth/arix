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
errors: std.ArrayList(TreeBuilderError),

pub fn init(alloc: std.mem.Allocator) TestAdapter {
    return .{
        .allocator = alloc,
        .errors = .empty,
    };
}

pub fn adapter(self: *TestAdapter) TreeAdapter {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

pub fn deinit(self: *TestAdapter) void {
    self.errors.deinit(self.allocator);
}

// Implement TreeAdapter's method.
pub fn handleError(ptr: *anyopaque, err: TreeBuilderError) void {
    const self: *TestAdapter = @ptrCast(@alignCast(ptr));
    self.errors.append(self.allocator, err) catch unreachable;
}
