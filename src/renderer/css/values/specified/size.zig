const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");
const Length = @import("Length.zig");

// https://www.w3.org/TR/css-sizing-3/#preferred-size-properties
pub const Size = union(enum) {
    auto,
    min_content,
    max_content,
    fit_content,
    stretch,
    length: Length,
    /// Percentage points: 50 represents 50%, not 0.5.
    percentage: f64,
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
        // Numbers without units can only be 0.
        .number => |number| if (number.value == 0)
            .{ .length = .{ .value = 0, .unit = .px } }
        else
            return null,
        .percentage => |percentage| if (percentage.value >= 0)
            .{ .percentage = percentage.value }
        else
            return null,
        .dimension => |dimension| blk: {
            if (!(dimension.value >= 0)) return null;
            inline for (std.meta.fields(Length.Unit)) |unit| {
                if (dimension.unit.eqlAscii(unit.name)) break :blk .{
                    .length = .{ .value = dimension.value, .unit = @enumFromInt(unit.value) },
                };
            }
            return null;
        },
        else => return null,
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
        try std.testing.expectEqual(@as(f64, 2.5), value.length.value);
        try std.testing.expectEqual(@as(Length.Unit, @enumFromInt(unit.value)), value.length.unit);
        try std.testing.expect(input.empty());
    }
}
