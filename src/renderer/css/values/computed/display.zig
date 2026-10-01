const SpecifiedDisplay = @import("../specified/display.zig").Display;
const Context = @import("Context.zig");

pub const Display = union(enum) {
    box: Box,
    internal: SpecifiedDisplay.Internal,
    none,
    contents,

    /// Computed inner/outer display types and optional list-item flag.
    pub const Box = struct {
        outside: SpecifiedDisplay.Outside = .@"inline",
        inside: SpecifiedDisplay.Inside = .flow,
        list_item: bool = false,
    };

    pub fn fromSpecified(value: SpecifiedDisplay, _: *const Context) Display {
        return switch (value) {
            .box => |box| .{ .box = .{ .outside = box.outside, .inside = box.inside } },
            .list_item => |item| .{ .box = .{
                .outside = item.outside,
                .inside = switch (item.inside) {
                    .flow => .flow,
                    .flow_root => .flow_root,
                },
                .list_item = true,
            } },
            .internal => |internal| .{ .internal = internal },
            .none => .none,
            .contents => .contents,
            .legacy => |legacy| .{ .box = .{ .inside = switch (legacy) {
                .inline_block => .flow_root,
                .inline_table => .table,
                .inline_flex => .flex,
                .inline_grid => .grid,
            } } },
        };
    }

    // A simplified implementation of blockification.
    // FIXME: See https://www.w3.org/TR/css-display-3/#transformations
    pub fn blockify(self: Display) Display {
        return switch (self) {
            .none, .contents => self,
            .internal => .{ .box = .{ .outside = .block } },
            .box => |box| .{ .box = .{
                .outside = .block,
                .inside = if (box.outside != .block and box.inside == .flow_root) .flow else box.inside,
                .list_item = box.list_item,
            } },
        };
    }
};
