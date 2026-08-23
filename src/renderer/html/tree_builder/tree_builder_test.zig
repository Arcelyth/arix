const std = @import("std");
const testing = std.testing;
const TreeBuilder = @import("TreeBuilder.zig");
const Element = @import("../../dom/Element.zig");
const Document = @import("../../dom/Document.zig");
const ln = @import("local_name");
const LocalName = ln.LocalName;
const TestAdapter = @import("TestAdapter.zig");

test "appropriatePlaceForInsertion - normal insertion without foster parenting" {
    const allocator = testing.allocator;
    var doc = Document.init();
    var test_adapter = TestAdapter.init(allocator);
    const adapter = test_adapter.adapter();
    var builder = TreeBuilder.init(allocator, adapter, false);
    defer builder.deinit();

    var html = Element.init(allocator, .NS_Html, LocalName.fromTag(.html), &doc);
    var div = Element.init(allocator, .NS_Html, LocalName.fromTag(.div), &doc);

    try builder.open_elements.append(&html);
    try builder.open_elements.append(&div);

    const loc = builder.appropriatePlaceForInsertion(null);
    try testing.expectEqual(div.asNode(), loc.last_child);
}
