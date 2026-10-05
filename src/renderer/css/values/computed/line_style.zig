const Context = @import("Context.zig");
const SpecifiedLineStyle = @import("../specified/line_style.zig").LineStyle;

pub const LineStyle = SpecifiedLineStyle;

pub fn fromSpecified(value: SpecifiedLineStyle, _: *const Context) LineStyle {
    return value;
}
