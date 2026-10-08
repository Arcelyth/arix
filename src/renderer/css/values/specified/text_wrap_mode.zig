const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");

/// https://drafts.csswg.org/css-text-4/#text-wrap-mode
pub const TextWrapMode = enum { wrap, nowrap };

pub fn parse(input: *Stream) ?TextWrapMode {
    const token = input.peekToken() orelse return null;
    if (token.* != .ident) return null;
    inline for (std.enums.values(TextWrapMode)) |value| {
        if (token.ident.eqlAscii(@tagName(value))) {
            input.advance();
            return value;
        }
    }
    return null;
}
