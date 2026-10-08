const Context = @import("Context.zig");
const specified = @import("../specified/font_size.zig");
const SpecifiedFontSize = specified.FontSize;

pub const FontSize = f64;

pub fn initial(context: *const Context) FontSize {
    return context.default_font_size;
}

pub fn fromSpecified(value: SpecifiedFontSize, context: *const Context) FontSize {
    const parent_size = if (context.inherited_style) |style| style.font_size else initial(context);
    return switch (value) {
        .absolute => |keyword| initial(context) * absoluteScale(keyword),
        .relative => |keyword| switch (keyword) {
            .larger => parent_size * context.relative_font_size_ratio,
            .smaller => parent_size / context.relative_font_size_ratio,
        },
        .length_percentage => |size| switch (size) {
            .percentage => |percentage| parent_size * (percentage / 100),
            .length => |length| blk: {
                var parent_context = context.*;
                parent_context.font_size = parent_size;
                // rem in the root's own font-size uses the default size.
                if (context.is_root) parent_context.root_font_size = initial(context);
                break :blk parent_context.computeLength(length);
            },
        },
    };
}

/// Later properties use this element's size for em lengths.
pub inline fn updateContext(value: FontSize, context: *Context) void {
    context.font_size = value;
    if (context.is_root) context.root_font_size = value;
}

/// CSS Fonts' suggested absolute-size scale and medium comes from UA settings.
/// https://drafts.csswg.org/css-fonts-4/#absolute-size-mapping
inline fn absoluteScale(value: specified.Absolute) f64 {
    return switch (value) {
        .@"xx-small" => 3.0 / 5.0,
        .@"x-small" => 3.0 / 4.0,
        .small => 8.0 / 9.0,
        .medium => 1,
        .large => 6.0 / 5.0,
        .@"x-large" => 3.0 / 2.0,
        .@"xx-large" => 2,
        .@"xxx-large" => 3,
    };
}
