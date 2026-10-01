const Stream = @import("../../syntax/ComponentValueStream.zig");
const Length = @import("Length.zig");
const length_percentage = @import("length_percentage.zig");

// https://www.w3.org/TR/css-box-3/#margin-physical
pub const Margin = union(enum) {
    auto,
    length_percentage: length_percentage.LengthPercentage,
};

pub fn parse(input: *Stream) ?Margin {
    if (input.peekToken()) |token| {
        if (token.* == .ident and token.ident.eqlAscii("auto")) {
            input.advance();
            return .auto;
        }
    }
    return .{ .length_percentage = length_percentage.parse(input, .any) orelse return null };
}
