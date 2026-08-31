const std = @import("std");

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
    ident: []const u21,
    function: []const u21,
    at_keyword: []const u21,
    hash: struct {
        value: []const u21,
        type_flag: HashType = .unrestricted,
    },
    string: []const u21,
    bad_string,
    url: []const u21,
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
        unit: []const u21,
    },

    unicode_range: struct {
        start: u21,
        end: u21,

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
