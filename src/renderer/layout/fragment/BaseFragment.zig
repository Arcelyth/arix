const BaseFragment = @This();

const Rect = @import("../../geometry/Rect.zig");

/// Position relative to the parent fragment's content origin, in CSS pixels.
/// Size covers the box's content area or the text run's advance and font height.
rect: Rect,
