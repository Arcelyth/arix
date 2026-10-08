const Context = @This();
const Length = @import("../specified/Length.zig");
const ComputedValues = @import("../../properties/registry.zig").ComputedValues;

font_size: f64,
root_font_size: f64,
x_height: f64,
zero_advance: f64,
viewport_width: f64,
viewport_height: f64,
inherited_style: ?*const ComputedValues = null,
/// UA preference for medium.
default_font_size: f64 = 16,
/// UA preference for larger/smaller. Spec recommends roughly 1.2–1.5.
relative_font_size_ratio: f64 = 1.2,
is_root: bool = false,

// https://www.w3.org/TR/css-values-3/#relative-lengths
// https://www.w3.org/TR/css-values-3/#absolute-lengths
pub fn computeLength(self: *const Context, length: Length) f64 {
    const scale: f64 = switch (length.unit) {
        .px => 1,
        .em => self.font_size,
        .ex => self.x_height,
        .ch => self.zero_advance,
        .rem => self.root_font_size,
        .vw => self.viewport_width / 100,
        .vh => self.viewport_height / 100,
        .vmin => @min(self.viewport_width, self.viewport_height) / 100,
        .vmax => @max(self.viewport_width, self.viewport_height) / 100,
        .cm => 96.0 / 2.54,
        .mm => 96.0 / 25.4,
        .q => 96.0 / 101.6,
        .in => 96,
        .pt => 96.0 / 72.0,
        .pc => 16,
    };
    return length.value * scale;
}
