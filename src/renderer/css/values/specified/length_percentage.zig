const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");
const Length = @import("Length.zig");

pub const LengthPercentage = union(enum) {
    length: Length,
    // 50 represents 50%, not 0.5.
    percentage: f64,
};

pub const Range = enum { any, non_negative };

pub fn parse(input: *Stream, comptime range: Range) ?LengthPercentage {
    const token = input.peekToken() orelse return null;
    const value: LengthPercentage = switch (token.*) {
        .number => |number| if (number.value == 0)
            .{ .length = .{ .value = 0, .unit = .px, }, }
        else
            return null,
        .percentage => |percentage| blk: {
            if (range == .non_negative and !(percentage.value >= 0)) return null;
            break :blk .{ .percentage = percentage.value };
        },
        .dimension => |dimension| blk: {
            if (range == .non_negative and !(dimension.value >= 0)) return null;
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
    return value;
}
