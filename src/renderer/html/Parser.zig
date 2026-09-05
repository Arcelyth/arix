const Parser = @This();

const std = @import("std");
const Vtable = @import("tree_builder/TreeAdapter.zig").VTable;
const TreeAdapter = @import("tree_builder/TreeAdapter.zig");
const e = @import("tree_builder/error.zig");
const TreeBuilderError = e.TreeBuilderError;
const testing = std.testing;

const vtable = Vtable{
    .handleErrorFn = handleError,
};

allocator: std.mem.Allocator,
errors: std.ArrayList(TreeBuilderError),

pub fn init(alloc: std.mem.Allocator) Parser {
    return .{
        .allocator = alloc,
        .errors = .empty,
    };
}

// --- Implement TreeAdapter ---

pub fn adapter(self: *Parser) TreeAdapter {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

pub fn deinit(self: *Parser) void {
    self.errors.deinit(self.allocator);
}

pub fn handleError(ptr: *anyopaque, err: TreeBuilderError) void {
    const self: *Parser = @ptrCast(@alignCast(ptr));
    self.errors.append(self.allocator, err) catch unreachable;
}
