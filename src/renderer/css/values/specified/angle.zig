const std = @import("std");
const Stream = @import("../../syntax/ComponentValueStream.zig");

pub const AngleUnit = enum {
    deg,
    grad,
    rad,
    turn,
};

pub const Angle = struct {
    value: f64,
    unit: AngleUnit,

    pub fn degrees(self: Angle) f64 {
        return self.value * switch (self.unit) {
            .deg => @as(f64, 1),
            .grad => 0.9,
            .rad => 180.0 / std.math.pi,
            .turn => 360,
        };
    }
};

/// https://www.w3.org/TR/css-values-3/#angles
pub fn parse(input: *Stream) ?Angle {
    const token = input.peekToken() orelse return null;
    if (token.* != .dimension) return null;
    inline for (std.enums.values(@FieldType(Angle, "unit"))) |unit| {
        if (token.dimension.unit.eqlAscii(@tagName(unit))) {
            input.advance();
            return .{
                .value = token.dimension.value,
                .unit = unit,
            };
        }
    }
    return null;
}
