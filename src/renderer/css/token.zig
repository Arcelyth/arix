const std = @import("std");
const String = @import("String.zig");

pub const HashType = enum {
    id,
    unrestricted,
};

pub const NumberType = enum {
    integer,
    number,
};

pub const Sign = enum {
    plus, // '+'
    minus, // '-'
};

pub const Token = union(enum) {
    ident: String,
    function: String,
    at_keyword: String,
    hash: struct {
        value: String,
        type_flag: HashType = .unrestricted,
    },
    string: String,
    bad_string,
    url: String,
    bad_url,

    delim: u21,

    number: struct {
        value: f64,
        sign: ?Sign = null,
        type_flag: NumberType = .integer,
    },
    percentage: struct {
        value: f64,
        sign: ?Sign = null,
    },
    dimension: struct {
        value: f64,
        sign: ?Sign = null,
        type_flag: NumberType = .integer,
        unit: String,
    },

    unicode_range: struct {
        start: u32,
        end: u32,

        pub inline fn isEmpty(self: @This()) bool {
            return self.end < self.start;
        }
    },

    whitespace,
    cdo, // <!--
    cdc, // -->
    colon, // :
    semicolon, // ;
    comma, // ,
    left_bracket, // [
    right_bracket, // ]
    left_paren, // (
    right_paren, // )
    left_brace, // {
    right_brace, // }
    eof,
};
