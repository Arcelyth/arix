/// A type-erased interface for handling TreeBuilder.
const TreeAdapter = @This();

const TreeBuilderError = @import("error.zig").TreeBuilderError;

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    handleErrorFn: *const fn (ptr: *anyopaque, err: TreeBuilderError) void,
};

pub fn handleError(self: TreeAdapter, err: TreeBuilderError) void {
    self.vtable.handleErrorFn(self.ptr, err);
}
