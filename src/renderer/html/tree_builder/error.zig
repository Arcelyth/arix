const std = @import("std");
const Token = @import("../tokenizer/token.zig").Token;
const types = @import("types.zig");
const InsertionMode = types.InsertionMode;

pub const TreeBuilderError = union(enum) {
    unexpected: struct { tk: Token, mode: InsertionMode },

    close_cell_without_cell,
    not_iframe_srcdoc,
    no_element_on_stack,
    end_tag_not_template,
    non_hidden_input,
    no_table_in_scope,
    invalid_start_tag_in_insertion_mode,
    null_character,
    non_whitespace_in_table_text,
    no_caption_in_table_scope,
    current_node_not_caption,
    invalid_tag_in_caption,
    current_node_not_colgroup,
    invalid_tag_in_column_group,

    pub fn format(self: TreeBuilderError, writer: anytype) !void {
        switch (self) {
            .unexpected => |info| {
                try writer.print(
                    "Unexpected token: {f} in insertion mode: {s}.",
                    .{ info.tk, @tagName(info.mode) },
                );
            },
            .close_cell_without_cell => {
                try writer.writeAll("Close cell without cell.");
            },
            .not_iframe_srcdoc => {
                try writer.writeAll("Document is not an iframe srcdoc document.");
            },
            .no_element_on_stack => {},
            .non_hidden_input => {},
        }
    }
};
