const std = @import("std");
const testing = std.testing;
const TreeBuilder = @import("TreeBuilder.zig");
const Element = @import("../../dom/Element.zig");
const ln = @import("local_name");
const LocalName = ln.LocalName;

test "appropriatePlaceForInsertion - normal insertion without foster parenting" {
    const allocator = testing.allocator;
    var builder = TreeBuilder.init(allocator);
    defer builder.deinit();

    var html = Element.init(.NS_Html, LocalName.fromTag(.html));
    var div = Element.init(.NS_Html, LocalName.fromTag(.div));

    try builder.open_elements.append(allocator, &html);
    try builder.open_elements.append(allocator, &div);

    const loc = builder.appropriatePlaceForInsertion(null);
    try testing.expectEqual(div, loc.last_child.*);
}
