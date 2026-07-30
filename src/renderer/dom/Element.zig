const Element = @This();

const Namespace = @import("namespace.zig").Namespace;
const Node = @import("Node.zig");
const std = @import("std");

node: Node,
ns: Namespace,
// TODO: use RawName
local_name: []const u8,

pub fn isMathMLTextIntegrationPoint(self: Element) bool {
    if (self.ns != .NS_MathML) return false;
    return std.mem.eql(u8, self.local_name, "mi") or
        std.mem.eql(u8, self.local_name, "mo") or
        std.mem.eql(u8, self.local_name, "mn") or
        std.mem.eql(u8, self.local_name, "ms") or
        std.mem.eql(u8, self.local_name, "mtext");
}

pub fn isHtmlIntegrationPoint(self: Element) bool {
    _ = self;
}

pub fn isMathMLAnnotationXml(self: Element) bool {
    _ = self;
}
