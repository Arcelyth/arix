const EventTarget = @This();
const BaseObj = @import("BaseObj.zig");

baseObj: BaseObj,

pub fn init() EventTarget {
    return .{ .baseObj = BaseObj.init() };
}
