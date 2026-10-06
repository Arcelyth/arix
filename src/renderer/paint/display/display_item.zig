const Rect = @import("../../geometry/Rect.zig");
const EdgeSizes = @import("../../geometry/EdgeSizes.zig");
const LineStyle = @import("../../css/values/specified/line_style.zig").LineStyle;

pub const DisplayItem = union(enum) {
    rect: RectDisplayItem,
    border: BorderDisplayItem,
};

pub const CommonItemProperties = struct {
    clip_rect: Rect,
};

pub const RectDisplayItem = struct {
    common: CommonItemProperties,
    /// CSS pixels in canvas coordinates.
    bounds: Rect,
    /// Unpremultiplied sRGB and alpha, each in [0, 1].
    color: [4]f64,
};

pub const BorderSide = struct {
    color: [4]f64 = .{ 0, 0, 0, 0 },
    style: LineStyle = .none,

    pub fn isVisible(self: BorderSide) bool {
        return self.style != .none and self.style != .hidden and self.color[3] > 0;
    }
};

pub const BorderRadius = struct {
    pub const Size = struct { width: f64 = 0, height: f64 = 0 };

    top_left: Size = .{},
    top_right: Size = .{},
    bottom_right: Size = .{},
    bottom_left: Size = .{},

    pub fn isZero(self: BorderRadius) bool {
        inline for (.{ "top_left", "top_right", "bottom_right", "bottom_left" }) |corner| {
            const radius = @field(self, corner);
            if (radius.width > 0 and radius.height > 0) return false;
        }
        return true;
    }
};

pub const BorderProperties = struct {
    top: BorderSide = .{},
    right: BorderSide = .{},
    bottom: BorderSide = .{},
    left: BorderSide = .{},
    radius: BorderRadius = .{},
};

pub const BorderDisplayItem = struct {
    common: CommonItemProperties,
    bounds: Rect,
    widths: EdgeSizes,
    details: BorderProperties,
};
