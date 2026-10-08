const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");

/// https://drafts.csswg.org/css-text-3/#propdef-white-space
pub const WhiteSpace = enum {
    normal,
    pre,
    nowrap,
    @"pre-wrap",
    @"break-spaces",
    @"pre-line",
};

pub fn parse(input: *Stream) ?WhiteSpace {
    const token = input.peekToken() orelse return null;
    if (token.* != .ident) return null;
    inline for (std.enums.values(WhiteSpace)) |value| {
        if (token.ident.eqlAscii(@tagName(value))) {
            input.advance();
            return value;
        }
    }
    return null;
}
