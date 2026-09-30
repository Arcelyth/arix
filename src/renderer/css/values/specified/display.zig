const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");

// https://www.w3.org/TR/css-display-3/#the-display-properties
pub const Display = union(enum) {
    box: Box,
    list_item: ListItem,
    internal: Internal,
    legacy: Legacy,
    none,
    /// Corresponding to the <display-box> in spec.
    contents,

    pub const Outside = enum {
        block,
        @"inline",
        run_in,
    };

    pub const Inside = enum {
        flow,
        flow_root,
        table,
        flex,
        grid,
        ruby,
    };

    /// Corresponding to the [ <display-outside> || <display-inside> ] in spec.
    pub const Box = struct {
        outside: Outside = .@"inline",
        inside: Inside = .flow,
    };

    pub const ListItem = struct {
        outside: Outside = .block,
        inside: enum { flow, flow_root } = .flow,
    };

    pub const Internal = enum {
        table_row_group,
        table_header_group,
        table_footer_group,
        table_row,
        table_cell,
        table_column_group,
        table_column,
        table_caption,
        ruby_base,
        ruby_text,
        ruby_base_container,
        ruby_text_container,
    };

    pub const Legacy = enum {
        inline_block,
        inline_table,
        inline_flex,
        inline_grid,
    };
};

const Keyword = union(enum) {
    outside: Display.Outside,
    inside: Display.Inside,
    standalone: Display,
    list_item,
};

const keywords = std.StaticStringMap(Keyword).initComptime([_]struct { []const u8, Keyword }{
    .{ "block", .{ .outside = .block } },
    .{ "inline", .{ .outside = .@"inline" } },
    .{ "run-in", .{ .outside = .run_in } },
    .{ "flow", .{ .inside = .flow } },
    .{ "flow-root", .{ .inside = .flow_root } },
    .{ "table", .{ .inside = .table } },
    .{ "flex", .{ .inside = .flex } },
    .{ "grid", .{ .inside = .grid } },
    .{ "ruby", .{ .inside = .ruby } },
    .{ "list-item", .list_item },
    .{ "none", .{ .standalone = .none } },
    .{ "contents", .{ .standalone = .contents } },
    .{ "inline-block", .{ .standalone = .{ .legacy = .inline_block } } },
    .{ "inline-table", .{ .standalone = .{ .legacy = .inline_table } } },
    .{ "inline-flex", .{ .standalone = .{ .legacy = .inline_flex } } },
    .{ "inline-grid", .{ .standalone = .{ .legacy = .inline_grid } } },
    .{ "table-row-group", .{ .standalone = .{ .internal = .table_row_group } } },
    .{ "table-header-group", .{ .standalone = .{ .internal = .table_header_group } } },
    .{ "table-footer-group", .{ .standalone = .{ .internal = .table_footer_group } } },
    .{ "table-row", .{ .standalone = .{ .internal = .table_row } } },
    .{ "table-cell", .{ .standalone = .{ .internal = .table_cell } } },
    .{ "table-column-group", .{ .standalone = .{ .internal = .table_column_group } } },
    .{ "table-column", .{ .standalone = .{ .internal = .table_column } } },
    .{ "table-caption", .{ .standalone = .{ .internal = .table_caption } } },
    .{ "ruby-base", .{ .standalone = .{ .internal = .ruby_base } } },
    .{ "ruby-text", .{ .standalone = .{ .internal = .ruby_text } } },
    .{ "ruby-base-container", .{ .standalone = .{ .internal = .ruby_base_container } } },
    .{ "ruby-text-container", .{ .standalone = .{ .internal = .ruby_text_container } } },
});

/// Parse the display grammar.
pub fn parse(input: *Stream) ?Display {
    var cursor = input.*;
    var outside: ?Display.Outside = null;
    var inside: ?Display.Inside = null;
    var list_item = false;
    var standalone: ?Display = null;
    var count: u8 = 0;

    cursor.discardWhitespace();
    while (!cursor.empty()) {
        // More than 3 keywords is not allowed.
        // display: block flow list-item;
        if (standalone != null or count == 3) return null;
        
        const name = cursor.consumeIdent() orelse return null;
        var lower: [keywords.max_len]u8 = undefined;
        const keyword = keywords.get(name.toAsciiLower(&lower) orelse return null) orelse return null;

        switch (keyword) {
            .outside => |value| {
                if (outside != null) return null;
                outside = value;
            },
            .inside => |value| {
                if (inside != null) return null;
                inside = value;
            },
            .list_item => {
                if (list_item) return null;
                list_item = true;
            },
            .standalone => |value| {
                if (count != 0) return null;
                standalone = value;
            },
        }
        count += 1;
        cursor.discardWhitespace();
    }
    if (count == 0) return null;

    const inner = inside orelse .flow;
    const result: Display = if (list_item) .{ .list_item = .{
        .outside = outside orelse .block,
        .inside = switch (inner) {
            .flow => .flow,
            .flow_root => .flow_root,
            else => return null,
        },
    } } else standalone orelse .{ .box = .{
        .outside = outside orelse if (inner == .ruby) .@"inline" else .block,
        .inside = inner,
    } };
    input.* = cursor;
    return result;
}
