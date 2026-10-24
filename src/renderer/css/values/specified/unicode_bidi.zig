const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");

/// Bidi scope and ordering.
/// https://drafts.csswg.org/css-writing-modes-3/#unicode-bidi
pub const UnicodeBidi = enum {
    normal,
    embed,
    isolate,
    @"bidi-override",
    @"isolate-override",
    plaintext,
};

pub fn parse(input: *Stream) ?UnicodeBidi {
    const token = input.peekToken() orelse return null;
    if (token.* != .ident) return null;
    inline for (std.enums.values(UnicodeBidi)) |value| {
        if (token.ident.eqlAscii(@tagName(value))) {
            input.advance();
            return value;
        }
    }
    return null;
}
