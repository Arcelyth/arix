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

pub fn cloneToken(alloc: std.mem.Allocator, tk: Token) std.mem.Allocator.Error!Token {
    return switch (tk) {
        .ident => |value| .{ .ident = try value.cloneDecoded(alloc) },
        .function => |value| .{ .function = try value.cloneDecoded(alloc) },
        .at_keyword => |value| .{ .at_keyword = try value.cloneDecoded(alloc) },
        .hash => |value| .{ .hash = .{
            .value = try value.value.cloneDecoded(alloc),
            .type_flag = value.type_flag,
        } },
        .string => |value| .{ .string = try value.cloneDecoded(alloc) },
        .url => |value| .{ .url = try value.cloneDecoded(alloc) },
        .dimension => |value| .{ .dimension = .{
            .value = value.value,
            .sign = value.sign,
            .type_flag = value.type_flag,
            .unit = try value.unit.cloneDecoded(alloc),
        } },
        inline else => |value, tag| @unionInit(Token, @tagName(tag), value),
    };
}
