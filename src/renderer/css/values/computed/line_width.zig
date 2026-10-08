const Context = @import("Context.zig");
const SpecifiedLineWidth = @import("../specified/line_width.zig").LineWidth;
const LineStyle = @import("line_style.zig").LineStyle;
const ResolvedContext = @import("../resolved.zig").Context;

pub const LineWidth = f64;

pub fn initial(context: *const Context) LineWidth {
    return fromSpecified(.medium, context);
}

pub fn fromSpecified(value: SpecifiedLineWidth, context: *const Context) LineWidth {
    const width = switch (value) {
        .thin => @as(f64, 1),
        .medium => @as(f64, 3),
        .thick => @as(f64, 5),
        .length => |length| context.computeLength(length),
    };
    return if (width > 0 and width < 1) 1 else @floor(width);
}

pub fn toResolvedValue(width: LineWidth, context: *const ResolvedContext) LineWidth {
    const style = switch (context.current_longhand) {
        .border_top_width => context.style.border_top_style,
        .border_right_width => context.style.border_right_style,
        .border_bottom_width => context.style.border_bottom_style,
        .border_left_width => context.style.border_left_style,
        else => return width,
    };
    return switch (style) {
        .none, .hidden => 0,
        else => width,
    };
}
