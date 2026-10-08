const std = @import("std");
const Stream = @import("../syntax/ComponentValueStream.zig");
const Value = @import("types.zig").Value;
const border = @import("border.zig");
const PropertyId = @import("registry.zig").PropertyId;

pub const Shorthand = struct {
    longhands: []const PropertyId,
    parse: *const fn (std.mem.Allocator, *Stream, []Value) bool,
};

pub const shorthands = .{
    .border = Shorthand{
        .longhands = &.{
            .border_top_width,    .border_top_style,    .border_top_color,
            .border_right_width,  .border_right_style,  .border_right_color,
            .border_bottom_width, .border_bottom_style, .border_bottom_color,
            .border_left_width,   .border_left_style,   .border_left_color,
        },
        .parse = &border.parseAll,
    },
    .border_top = Shorthand{
        .longhands = &.{
            .border_top_width,
            .border_top_style,
            .border_top_color,
        },
        .parse = &border.parseEdge,
    },
    .border_right = Shorthand{
        .longhands = &.{
            .border_right_width,
            .border_right_style,
            .border_right_color,
        },
        .parse = &border.parseEdge,
    },
    .border_bottom = Shorthand{
        .longhands = &.{
            .border_bottom_width,
            .border_bottom_style,
            .border_bottom_color,
        },
        .parse = &border.parseEdge,
    },
    .border_left = Shorthand{
        .longhands = &.{
            .border_left_width,
            .border_left_style,
            .border_left_color,
        },
        .parse = &border.parseEdge,
    },
    .border_width = Shorthand{
        .longhands = &.{
            .border_top_width,
            .border_right_width,
            .border_bottom_width,
            .border_left_width,
        },
        .parse = &border.parseWidths,
    },
    .border_style = Shorthand{
        .longhands = &.{
            .border_top_style,
            .border_right_style,
            .border_bottom_style,
            .border_left_style,
        },
        .parse = &border.parseStyles,
    },
    .border_color = Shorthand{
        .longhands = &.{
            .border_top_color,
            .border_right_color,
            .border_bottom_color,
            .border_left_color,
        },
        .parse = &border.parseColors,
    },
};
