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

    /// Returns whether consecutive whitespace characters are collapsed.
    pub fn collapses(self: WhiteSpace) bool {
        return switch (self) {
            .normal, .nowrap, .@"pre-line" => true,
            .pre, .@"pre-wrap", .@"break-spaces" => false,
        };
    }

    /// Returns whether automatic line wrapping is allowed.
    pub fn wraps(self: WhiteSpace) bool {
        return self != .pre and self != .nowrap;
    }

    /// Returns whether explicit line breaks are preserved.
    pub fn preservesBreaks(self: WhiteSpace) bool {
        return self != .normal and self != .nowrap;
    }
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
