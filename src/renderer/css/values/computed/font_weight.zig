const Context = @import("Context.zig");
const SpecifiedFontWeight = @import("../specified/font_weight.zig").FontWeight;
pub const FontWeight = f64;

/// https://drafts.csswg.org/css-fonts-4/#relative-weights
pub fn fromSpecified(value: SpecifiedFontWeight, context: *const Context) FontWeight {
    const parent = if (context.inherited_style) |style| style.font_weight else 400;
    return switch (value) {
        .number => |number| number,
        .bolder => if (parent < 350)
            400
        else if (parent < 550)
            700
        else
            @max(900, parent),
        .lighter => if (parent < 100)
            parent
        else if (parent < 550)
            100
        else if (parent < 750)
            400
        else
            700,
    };
}
