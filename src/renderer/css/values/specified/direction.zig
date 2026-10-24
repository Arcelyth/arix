const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");

/// Inline base direction.
/// https://drafts.csswg.org/css-writing-modes-3/#direction
pub const Direction = enum { ltr, rtl };

pub fn parse(input: *Stream) ?Direction {
    const token = input.peekToken() orelse return null;
    if (token.* != .ident) return null;
    inline for (std.enums.values(Direction)) |value| {
        if (token.ident.eqlAscii(@tagName(value))) {
            input.advance();
            return value;
        }
    }
    return null;
}
