const Context = @import("Context.zig");
const SpecifiedLineWidth = @import("../specified/line_width.zig").LineWidth;
const LineStyle = @import("line_style.zig").LineStyle;

pub const LineWidth = f64;

pub fn fromSpecified(value: SpecifiedLineWidth, context: *const Context) LineWidth {
    const width = switch (value) {
        .thin => @as(f64, 1),
        .medium => @as(f64, 3),
        .thick => @as(f64, 5),
        .length => |length| context.computeLength(length),
    };
    return if (width > 0 and width < 1) 1 else @floor(width);
}
