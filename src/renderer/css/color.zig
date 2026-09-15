pub const Space = enum {
    srgb,
    srgb_linear,
    display_p3,
    a98_rgb,
    prophoto_rgb,
    rec2020,
    xyz_d50,
    xyz_d65,
    hsl,
    hwb,
    lab,
    lch,
    oklab,
    oklch,
};

pub const Absolute = struct {
    space: Space = .srgb,
    channels: [3]?f64,
    alpha: ?f64 = 1,
};

pub const Color = union(enum) {
    absolute: Absolute,
    current_color,
    /// Index into the static system color table; not a resolved platform color.
    system: usize,
};

