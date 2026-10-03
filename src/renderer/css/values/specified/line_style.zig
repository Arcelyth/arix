const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");

/// https://www.w3.org/TR/css-backgrounds-3/#typedef-line-style
pub const LineStyle = enum {
    none,
    hidden,
    dotted,
    dashed,
    solid,
    double,
    groove,
    ridge,
    inset,
    outset,
};

pub fn parse(input: *Stream) ?LineStyle {
    const token = input.peekToken() orelse return null;
    if (token.* != .ident) return null;
    inline for (std.meta.fields(LineStyle)) |field| {
        if (token.ident.eqlAscii(field.name)) {
            input.advance();
            return @enumFromInt(field.value);
        }
    }
    return null;
}
