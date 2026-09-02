/// CSS Syntax §5.2 parsing result types.
const token = @import("token.zig");

// FIXME: Use Strale will be better?
pub const String = []const u21;

pub const Stylesheet = struct {
    rules: []Rule = &.{},
};

pub const Rule = union(enum) {
    at_rule: AtRule,
    qualified_rule: QualifiedRule,
};

pub const AtRule = struct {
    name: String,
    prelude: []ComponentValue = &.{},
    declarations: ?[]Declaration = null,
    child_rules: ?[]Rule = null,
};

pub const QualifiedRule = struct {
    prelude: []ComponentValue = &.{},
    declarations: []Declaration = &.{},
    child_rules: []Rule = &.{},
};

pub const Declaration = struct {
    name: String,
    value: []ComponentValue = &.{},
    important: bool = false,
    original_text: ?String = null,
};

pub const ComponentValue = union(enum) {
    preserved_token: PreservedToken,
    function: Function,
    simple_block: SimpleBlock,
};

pub const Function = struct {
    name: String,
    value: []ComponentValue = &.{},
};

pub const BlockToken = enum {
    left_brace,
    left_bracket,
    left_paren,
};

pub const SimpleBlock = struct {
    associated_token: BlockToken,
    value: []ComponentValue = &.{},
};

pub const PreservedToken = union(enum) {
    ident: String,
    at_keyword: String,
    hash: struct {
        value: String,
        type_flag: token.HashType = .unrestricted,
    },
    string: String,
    bad_string,
    url: String,
    bad_url,
    delim: u21,
    number: struct {
        value: f64,
        sign: ?token.Sign = null,
        type_flag: token.NumberType = .integer,
    },
    percentage: struct {
        value: f64,
        sign: ?token.Sign = null,
    },
    dimension: struct {
        value: f64,
        sign: ?token.Sign = null,
        type_flag: token.NumberType = .integer,
        unit: String,
    },
    unicode_range: struct {
        start: u32,
        end: u32,
    },
    whitespace,
    cdo,
    cdc,
    colon,
    semicolon,
    comma,
    right_bracket,
    right_paren,
    right_brace,
};
