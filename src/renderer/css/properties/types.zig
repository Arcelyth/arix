const std = @import("std");
const Size = @import("../values/specified/size.zig").Size;
const Margin = @import("../values/specified/margin.zig").Margin;
const LengthPercentage = @import("../values/specified/length_percentage.zig").LengthPercentage;
const specified = @import("../values/specified.zig");
const Display = specified.Display;
const Color = specified.Color;
const LineWidth = specified.LineWidth;
const LineStyle = specified.LineStyle;
const CSSWideKeyword = specified.CSSWideKeyword;
const FontFamily = specified.FontFamily;
const FontSize = specified.FontSize;
const FontStyle = specified.FontStyle;
const FontWeight = specified.FontWeight;
const WhiteSpace = specified.WhiteSpace;
const LineHeight = specified.LineHeight;
pub const PropertyId = @import("registry.zig").PropertyId;

/// Parsed specified values, not yet selected by the cascade or computed.
pub const Value = union(enum) {
    font_family: FontFamily,
    font_size: FontSize,
    font_weight: FontWeight,
    font_style: FontStyle,
    size: Size,
    margin: Margin,
    padding: LengthPercentage,
    display: Display,
    color: Color,
    line_width: LineWidth,
    line_style: LineStyle,
    css_wide: CSSWideKeyword,
    line_height: LineHeight,
    white_space: WhiteSpace,

    pub fn deinit(self: Value, allocator: std.mem.Allocator) void {
        switch (self) {
            .font_family => |family| family.deinit(allocator),
            else => {},
        }
    }
};

pub const Declaration = struct {
    property: PropertyId,
    value: Value,
    important: bool = false,
};
