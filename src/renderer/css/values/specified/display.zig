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
