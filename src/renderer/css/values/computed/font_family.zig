const Context = @import("Context.zig");
pub const FontFamily = @import("../specified/font_family.zig").FontFamily;

pub fn initial(context: *const Context) FontFamily {
    return context.default_font_family;
}

pub fn fromSpecified(value: FontFamily, _: *const Context) FontFamily {
    return value;
}
