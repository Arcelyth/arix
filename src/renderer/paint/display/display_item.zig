const Rect = @import("../../geometry/Rect.zig");
const EdgeSizes = @import("../../geometry/EdgeSizes.zig");
const LineStyle = @import("../../css/values/specified/line_style.zig").LineStyle;
const std = @import("std");
const Point = @import("../../geometry.zig").Point;
const Font = @import("../../font/platform.zig").backend.Font;

pub const DisplayItem = union(enum) {
    rect: RectDisplayItem,
    border: BorderDisplayItem,
    text: TextDisplayItem,
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

pub const TextDisplayItem = struct {
    pub const Glyph = struct {
        id: u16,
        /// CSS pixels relative to the baseline origin, with Y increasing upward.
        position: Point,
    };

    common: CommonItemProperties,
    /// Owned font and glyphs, independent of the fragment tree.
    font: Font,
    glyphs: []const Glyph,
    /// CSS pixels in canvas coordinates, with Y increasing downward.
    baseline_origin: Point,
    /// The shaping run's text matrix: columns (a, b), (c, d), (tx, ty).
    text_matrix: [3]Point,
    color: [4]f64,

    pub fn deinit(self: TextDisplayItem, allocator: std.mem.Allocator) void {
        self.font.deinit();
        allocator.free(self.glyphs);
    }
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
