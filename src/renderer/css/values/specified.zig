pub const Length = @import("specified/Length.zig");
pub const Size = @import("specified/size.zig").Size;
pub const Color = @import("specified/color.zig").Color;
pub const Display = @import("specified/display.zig").Display;
pub const Margin = @import("specified/margin.zig").Margin;
pub const LineWidth = @import("specified/line_width.zig").LineWidth;
pub const LineStyle = @import("specified/line_style.zig").LineStyle;
pub const LengthPercentage = @import("specified/length_percentage.zig").LengthPercentage;
pub const CSSWideKeyword = @import("specified/css_wide_keyword.zig").CSSWideKeyword;
pub const FontSize = @import("specified/font_size.zig").FontSize;
pub const FontFamily = @import("specified/font_family.zig").FontFamily;
pub const FontStyle = @import("specified/font_style.zig").FontStyle;
pub const FontWeight = @import("specified/font_weight.zig").FontWeight;
pub const Angle = @import("specified/angle.zig").Angle;
pub const LineHeight = @import("specified/line_height.zig").LineHeight;
pub const TextWrapMode = @import("specified/text_wrap_mode.zig").TextWrapMode;

test {
    @import("std").testing.refAllDecls(@This());
}
