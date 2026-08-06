/// This object serves as the basic inheritance hierarchy.
const BaseObj = @This();

const VTable = struct {
    //  The virtual functions may like:
    //  destroy: *const fn (*anyopaque) void,
};

vtable: *const VTable,

pub fn init() BaseObj {
    return .{ .vtable = &VTable{} };
}
