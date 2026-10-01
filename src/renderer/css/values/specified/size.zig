const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");
const Length = @import("Length.zig");
const length_percentage = @import("length_percentage.zig");

// https://www.w3.org/TR/css-sizing-3/#preferred-size-properties
pub const Size = union(enum) {
    auto,
    min_content,
    max_content,
    fit_content,
    stretch,
    length_percentage: length_percentage.LengthPercentage,
};

/// Consume a non-negative literal size, leaving input unchanged on mismatch.
pub fn parse(input: *Stream) ?Size {
    const token = input.peekToken() orelse return null;
    const size: Size = switch (token.*) {
        .ident => |name| blk: {
            if (name.eqlAscii("auto")) break :blk .auto;
            if (name.eqlAscii("min-content")) break :blk .min_content;
            if (name.eqlAscii("max-content")) break :blk .max_content;
            if (name.eqlAscii("fit-content")) break :blk .fit_content;
            if (name.eqlAscii("stretch")) break :blk .stretch;
            return null;
        },
        else => return .{ .length_percentage = length_percentage.parse(input, .non_negative) orelse return null },
    };
    input.advance();
    return size;
}

test "values specified size: check all length units" {
    const ComponentValue = @import("../../syntax/parsing_results.zig").ComponentValue;
    const String = @import("../../String.zig");
    inline for (std.meta.fields(Length.Unit)) |unit| {
        const values = [_]ComponentValue{.{ .preserved_token = .{ .dimension = .{
            .value = 2.5,
            .unit = String.fromSource(unit.name),
        } } }};
        var input = Stream.init(&values);
        const value = parse(&input).?;
        try std.testing.expectEqual(@as(f64, 2.5), value.length_percentage.length.value);
        try std.testing.expectEqual(@as(Length.Unit, @enumFromInt(unit.value)), value.length_percentage.length.unit);
        try std.testing.expect(input.empty());
    }
}
