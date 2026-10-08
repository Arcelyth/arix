const Context = @import("Context.zig");
const SpecifiedFontStyle = @import("../specified/font_style.zig").FontStyle;

pub const FontStyle = union(enum) { normal, italic, left, right, oblique: f64 };

pub fn fromSpecified(value: SpecifiedFontStyle, _: *const Context) FontStyle {
    return switch (value) {
        .oblique => |angle| .{ .oblique = angle.degrees() },
        inline else => |_, tag| @unionInit(FontStyle, @tagName(tag), {}),
    };
}
