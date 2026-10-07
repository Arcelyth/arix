const Stream = @import("../../syntax/ComponentValueStream.zig");

/// https://www.w3.org/TR/css-fonts-4/#font-weight-prop
pub const FontWeight = union(enum) {
    number: f64,
    bolder,
    lighter,
};

pub fn parse(input: *Stream) ?FontWeight {
    const token = input.peekToken() orelse return null;
    const result: FontWeight = switch (token.*) {
        .number => |number| if (number.value >= 1 and number.value <= 1000)
            .{ .number = number.value }
        else
            return null,
        .ident => |name| if (name.eqlAscii("normal"))
            .{ .number = 400 }
        else if (name.eqlAscii("bold"))
            .{ .number = 700 }
        else if (name.eqlAscii("bolder"))
            .bolder
        else if (name.eqlAscii("lighter"))
            .lighter
        else
            return null,
        else => return null,
    };
    input.advance();
    return result;
}
