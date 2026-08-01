const std = @import("std");
const testing = std.testing;

const local_name = @import("local_name");

test "static tag names" {
    const html = local_name.LocalName.fromSlice("html");
    const div = local_name.LocalName.fromSlice("div");

    try testing.expect(html == .static);
    try testing.expect(div == .static);

    try testing.expect(html.is(.html));
    try testing.expect(div.is(.div));
}

test "unknown names are dynamic" {
    const custom = local_name.LocalName.fromSlice("custom-element");

    try testing.expect(custom == .dynamic);
    try testing.expectEqualStrings(
        "custom-element",
        custom.dynamic,
    );
}

test "static equality" {
    const a = local_name.LocalName.fromSlice("body");
    const b = local_name.LocalName.fromSlice("body");
    try testing.expect(a.eql(b));

    const c = local_name.LocalName.fromSlice("div");
    const d = local_name.LocalName.fromSlice("span");
    try testing.expect(!c.eql(d));
}

test "dynamic equality" {
    const a = local_name.LocalName.fromSlice("my-tag");
    const b = local_name.LocalName.fromSlice("my-tag");

    try testing.expect(a.eql(b));
}

test "static and dynamic with same bytes are not equal" {
    const static_name = local_name.LocalName.fromSlice("div");

    const dynamic_name: local_name.LocalName = .{
        .dynamic = "div",
    };

    try testing.expect(!static_name.eql(dynamic_name));
}

