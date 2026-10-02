const BoxFragment = @This();
const ComputedStyle = @import("../../style/computed.zig").ComputedStyle;
const EgdeSizes = @import("../../geometry/EdgeSizes.zig");
const BaseFragment = @import("BaseFragment.zig");
const LayoutBoxBase = @import("../LayoutBoxBase.zig");

base: BaseFragment,
style: ComputedStyle,
source: LayoutBoxBase.Source,

padding: EgdeSizes = .{},
border: EgdeSizes = .{},
margin: EgdeSizes = .{},
