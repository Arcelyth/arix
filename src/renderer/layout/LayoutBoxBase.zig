const LayoutBoxBase = @This();

const std = @import("std");
const Element = @import("../dom/Element.zig");
const ComputedStyle = @import("../style/computed/ComputedStyle.zig");
const Display = @import("../css/values/computed/display.zig").Display;
const registry = @import("../css/properties/registry.zig");
const Fragment = @import("fragment.zig").Fragment;

pub const Source = union(enum) {
    principal: *const Element,
    anonymous,
    // FIXME:
    marker: *const Element,
};

source: Source,
style: ComputedStyle,
/// Geometry produced later by layout; not part of the computed CSS values.
fragments: std.ArrayList(Fragment) = .empty,

pub fn deinit(self: *LayoutBoxBase, allocator: std.mem.Allocator) void {
    self.fragments.deinit(allocator);
}

/// Anonymous boxes inherit through the box tree; non-inherited properties
/// have their initial values. Construction supplies the anonymous display.
pub fn anonymous(parent_style: *const ComputedStyle, display: Display.Box) LayoutBoxBase {
    var style: ComputedStyle = .{};
    inline for (std.meta.fields(registry.PropertyId)) |field| {
        if (@field(registry.definitions, field.name).inherited)
            @field(style.values, field.name) = @field(parent_style.values, field.name);
    }
    style.values.display = .{ .box = display };
    return .{ .source = .anonymous, .style = style };
}
