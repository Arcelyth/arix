const BoxFragment = @This();
const ComputedStyle = @import("../../style/computed.zig").ComputedStyle;
const EgdeSizes = @import("../../geometry/EdgeSizes.zig");
const BaseFragment = @import("BaseFragment.zig");

base: BaseFragment,
style: ComputedStyle,

padding: EgdeSizes = .{},
border: EgdeSizes = .{},
margin: EgdeSizes = .{},
