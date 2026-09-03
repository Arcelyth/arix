/// Implementation of CSS Syntax §5.2 parsing result types.
const token = @import("token.zig");

// FIXME: Use Strale will be better?
pub const String = @import("String.zig");

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

// For 5.5.5.
pub const BlockItem = union(enum) {
    rule: Rule,
    declarations: []Declaration,
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

pub fn preservedToken(tk: token.Token) PreservedToken {
    return switch (tk) {
        .function, .left_bracket, .left_paren, .left_brace, .eof => unreachable,
        .hash => |value| .{ .hash = .{
            .value = value.value,
            .type_flag = value.type_flag,
        } },
        .number => |value| .{ .number = .{
            .value = value.value,
            .sign = value.sign,
            .type_flag = value.type_flag,
        } },
        .percentage => |value| .{ .percentage = .{
            .value = value.value,
            .sign = value.sign,
        } },
        .dimension => |value| .{ .dimension = .{
            .value = value.value,
            .sign = value.sign,
            .type_flag = value.type_flag,
            .unit = value.unit,
        } },
        .unicode_range => |value| .{ .unicode_range = .{
            .start = value.start,
            .end = value.end,
        } },
        inline else => |value, tag| @unionInit(
            PreservedToken,
            @tagName(tag),
            value,
        ),
    };
}
