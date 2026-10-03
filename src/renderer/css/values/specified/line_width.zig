const Stream = @import("../../syntax/ComponentValueStream.zig");
const Length = @import("Length.zig");
const length_percentage = @import("length_percentage.zig");

/// https://www.w3.org/TR/css-backgrounds-3/#typedef-line-width
pub const LineWidth = union(enum) {
    thin,
    medium,
    thick,
    length: Length,
};

pub fn parse(input: *Stream) ?LineWidth {
    if (input.peekToken()) |token| {
        if (token.* == .ident) {
            const width: LineWidth =
                if (token.ident.eqlAscii("thin")) .thin else if (token.ident.eqlAscii("medium")) .medium else if (token.ident.eqlAscii("thick")) .thick else return null;

            input.advance();
            return width;
        }
        // Percentages are not lengths.
        if (token.* == .percentage) return null;
    }
    const value = length_percentage.parse(input, .non_negative) orelse return null;
    return .{ .length = value.length };
}
