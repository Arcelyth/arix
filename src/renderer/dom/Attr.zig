const Attr = @This();
const Namespace = @import("namespace.zig").Namespace;
const ln = @import("local_name");
const LocalName = ln.LocalName;
const Element = @import("Element.zig");
const strale = @import("strale");
const StraleUtf8Global = strale.StraleUtf8Global;

// namespace
ns: ?Namespace,
prefix: ?LocalName,
local_name: LocalName,
value: StraleUtf8Global,
element: ?*Element,

pub fn init(local: LocalName) Attr {
    return .{
        .ns = null,
        .prefix = null,
        .local_name = local,
        .value = StraleUtf8Global.init(),
        .element = null,
    };
}

pub fn deinit(self: *Attr) void {
    self.value.deinit();
}
