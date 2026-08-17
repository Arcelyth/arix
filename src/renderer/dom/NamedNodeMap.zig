const NamedNodeMap = @This();

const Element = @import("Element.zig");
owner: ?*Element,

pub fn init(el: ?*Element) NamedNodeMap {
    return .{
        .owner = el,
    };
}

