const Size = @import("../values/specified/size.zig").Size;

pub const PropertyId = @import("registry.zig").PropertyId;

// https://www.w3.org/TR/css-cascade-5/#defaulting-keywords
pub const CSSWideKeyword = enum {
    initial,
    inherit,
    unset,
    revert,
    revert_layer,
};

/// Parsed specified values, not yet selected by the cascade or computed.
pub const Value = union(enum) {
    size: Size,
    css_wide: CSSWideKeyword,
};

pub const Declaration = struct {
    property: PropertyId,
    value: Value,
    important: bool = false,
};
