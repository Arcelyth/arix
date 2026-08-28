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
    unexpected_td_th_in_table_body,
    no_table_section_in_scope,
    end_table_without_table_body,
    invalid_tag_in_table_body,
    no_tr_in_table_scope,
    end_tr_without_tr_in_scope,
    end_table_without_tr_in_scope,
    end_table_section_without_scope,
    invalid_end_tag_in_row,
    end_cell_without_cell_in_scope,
    current_node_not_cell,
    invalid_tag_in_cell,
    end_table_element_without_scope,
    invalid_tag_in_template,
    eof_in_template,
    end_html_with_frameset_ok,
    end_frameset_with_html_current_node,
    eof_in_frameset,
    current_node_not_p,
    unexpected_node,
    xml_xlink_not_valid,

    pub fn format(self: TreeBuilderError, writer: anytype) !void {
        switch (self) {
            .unexpected => |info| {
                try writer.print(
                    "Unexpected token: {f} in insertion mode: {s}.",
                    .{ info.tk, @tagName(info.mode) },
                );
            },
            .close_cell_without_cell => try writer.writeAll("Close cell without cell in scope."),

            .not_iframe_srcdoc => try writer.writeAll("Document is not an iframe srcdoc document."),

            .no_element_on_stack => try writer.writeAll("No element on stack of open elements."),

            .end_tag_not_template => try writer.writeAll("End tag is not template."),

            .non_hidden_input => try writer.writeAll("Input element is not hidden."),

            .no_table_in_scope => try writer.writeAll("No table element in table scope."),

            .invalid_start_tag_in_insertion_mode => try writer.writeAll("Invalid start tag in insertion mode."),

            .null_character => try writer.writeAll("Null character in input stream."),

            .non_whitespace_in_table_text => try writer.writeAll("Non-whitespace character in table text."),

            .no_caption_in_table_scope => try writer.writeAll("No caption element in table scope."),

            .current_node_not_caption => try writer.writeAll("Current node is not caption."),

            .invalid_tag_in_caption => try writer.writeAll("Invalid tag in caption insertion mode."),

            .current_node_not_colgroup => try writer.writeAll("Current node is not colgroup."),

            .invalid_tag_in_column_group => try writer.writeAll("Invalid tag in column group insertion mode."),

            .unexpected_td_th_in_table_body => try writer.writeAll("Unexpected td or th start tag in table body."),

            .no_table_section_in_scope => try writer.writeAll("No table section element in scope."),

            .end_table_without_table_body => try writer.writeAll("End table without table body section."),

            .invalid_tag_in_table_body => try writer.writeAll("Invalid tag in table body insertion mode."),

            .no_tr_in_table_scope => try writer.writeAll("No tr element in table scope."),

            .end_tr_without_tr_in_scope => try writer.writeAll("End tr without tr in scope."),

            .end_table_without_tr_in_scope => try writer.writeAll("End table without tr in scope."),

            .end_table_section_without_scope => try writer.writeAll("End table section without element in scope."),

            .invalid_end_tag_in_row => try writer.writeAll("Invalid end tag in table row."),

            .end_cell_without_cell_in_scope => try writer.writeAll("End cell without cell in scope."),

            .current_node_not_cell => try writer.writeAll("Current node is not table cell."),

            .invalid_tag_in_cell => try writer.writeAll("Invalid tag in table cell insertion mode."),

            .end_table_element_without_scope => try writer.writeAll("End table element without element in scope."),

            .invalid_tag_in_template => try writer.writeAll("Invalid tag in template insertion mode."),

            .eof_in_template => try writer.writeAll("EOF in template."),

            .end_html_with_frameset_ok => try writer.writeAll("End html tag while frameset-ok flag is set."),

            .end_frameset_with_html_current_node => try writer.writeAll("End frameset while current node is html."),

            .eof_in_frameset => try writer.writeAll("EOF in frameset."),

            .current_node_not_p => try writer.writeAll("Current node is not a p element."),

            .unexpected_node => try writer.writeAll("Unexpected node."),

            .xml_xlink_not_valid => try writer.writeAll("Xml or XLink not valid"),
        }
    }
};
