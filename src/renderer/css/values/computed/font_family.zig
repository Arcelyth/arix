const Context = @import("Context.zig");
pub const FontFamily = @import("../specified/font_family.zig").FontFamily;

pub fn fromSpecified(value: FontFamily, _: *const Context) FontFamily {
    return value;
}
