const Size = @import("../values/specified/size.zig").Size;
const Margin = @import("../values/specified/margin.zig").Margin;
const LengthPercentage = @import("../values/specified/length_percentage.zig").LengthPercentage;
const Display = @import("../values/specified/display.zig").Display;
const Color = @import("../values/specified/color.zig").Color;
const LineWidth = @import("../values/specified/line_width.zig").LineWidth;
const LineStyle = @import("../values/specified/line_style.zig").LineStyle;
const CSSWideKeyword = @import("../values/specified.zig").CSSWideKeyword;
const FontFamily = @import("../values/specified/font_family.zig").FontFamily;
const FontSize = @import("../values/specified/font_size.zig").FontSize;
const FontStyle = @import("../values/specified/font_style.zig").FontStyle;
const FontWeight = @import("../values/specified/font_weight.zig").FontWeight;
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
};

pub const Declaration = struct {
    property: PropertyId,
    value: Value,
    important: bool = false,
};
