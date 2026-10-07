const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");
const length_percentage = @import("length_percentage.zig");
const LengthPercentage = length_percentage.LengthPercentage;

pub const Absolute = enum {
    @"xx-small",
    @"x-small",
    small,
    medium,
    large,
    @"x-large",
    @"xx-large",
    @"xxx-large",
};

pub const Relative = enum { smaller, larger };

/// https://www.w3.org/TR/css-fonts-4/#font-size-prop
pub const FontSize = union(enum) {
    absolute: Absolute,
    relative: Relative,
    length_percentage: LengthPercentage,
};

pub fn parse(input: *Stream) ?FontSize {
    if (input.peekToken()) |token| {
        if (token.* == .ident) {
            inline for (std.enums.values(Absolute)) |value| {
                if (token.ident.eqlAscii(@tagName(value))) {
                    input.advance();
                    return .{ .absolute = value };
                }
            }
            inline for (std.enums.values(Relative)) |value| {
                if (token.ident.eqlAscii(@tagName(value))) {
                    input.advance();
                    return .{ .relative = value };
                }
            }
        }
    }
    return .{
        .length_percentage = length_percentage.parse(input, .non_negative) orelse return null,
    };
}
