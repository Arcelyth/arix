const Stream = @import("../../syntax/ComponentValueStream.zig");
const length_percentage = @import("length_percentage.zig");
const LengthPercentage = length_percentage.LengthPercentage;

/// https://drafts.csswg.org/css-inline-3/#propdef-line-height
pub const LineHeight = union(enum) {
    normal,
    number: f64,
    length_percentage: LengthPercentage,
};

pub fn parse(input: *Stream) ?LineHeight {
    const token = input.peekToken() orelse return null;
    if (token.* == .ident and token.ident.eqlAscii("normal")) {
        input.advance();
        return .normal;
    }
    if (token.* == .number) {
        if (!(token.number.value >= 0)) return null;
        input.advance();
        return .{ .number = token.number.value };
    }
    return .{
        .length_percentage = length_percentage.parse(input, .non_negative) orelse return null,
    };
}
