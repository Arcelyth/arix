const TreeBuilder = @This();

const std = @import("std");
const token = @import("../tokenizer/token.zig");

const InsertionMode = enum {
    Initial,
    BeforeHtml,
    BeforeHead,
    InHead,
    InHeadNoscript,
    AfterHead,
    InBody,
    Text,
    InTable,
    InTableText,
    InCaption,
    InColumnGroup,
    InTableBody,
    InRow,
    InCell,
    InTemplate,
    AfterBody,
    InFrameset,
    AfterFrameset,
    AfterAfterBody,
    AfterAfterFrameset,
};

const ScriptingMode = enum {
    Normal,
    Disabled,
    Inert,
    Fragment,
};

// InsertionMode
insert_mode: InsertionMode,
// Original Insertion Mode
orig_insert_mode: InsertionMode,
// Template Insertion Mode
temp_insert_modes: std.ArrayList(InsertionMode),
fragment_case: bool,
scripting_mode: ScriptingMode,
foster_parenting: bool,
frameset_ok: bool,

pub fn init() TreeBuilder {
    return TreeBuilder{
        .insert_mode = .Initial,
        .orig_insert_mode = .Initial,
        .temp_insert_modes = .empty,
        .fragment_case = false,
        .scripting_mode = .Normal,
        .foster_parenting = false,
        .frameset_ok = false,
    };
}

// Implement TokenIngester.
pub fn handle_token(self: *TreeBuilder, tk: token.Token) void {
    _ = self;
    _ = tk;
} 
