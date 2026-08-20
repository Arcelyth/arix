const std = @import("std");
const testing = std.testing;

const local_name = @import("local_name");

test "static tag names" {
    const html = try local_name.LocalName.fromSlice("html");
    const div = try local_name.LocalName.fromSlice("div");

    try testing.expect(html == .static);
    try testing.expect(div == .static);

    try testing.expect(html.is(.html));
    try testing.expect(div.is(.div));
}

test "unknown names are dynamic" {
    const custom = try local_name.LocalName.fromSlice("custom-element");

    try testing.expect(custom == .dynamic);
    try testing.expectEqualStrings(
        "custom-element",
        custom.dynamic.slice(),
    );
}

test "static equality" {
    const a = try local_name.LocalName.fromSlice("body");
    const b = try local_name.LocalName.fromSlice("body");
    try testing.expect(a.eql(b));

    const c = try local_name.LocalName.fromSlice("div");
    const d = try local_name.LocalName.fromSlice("span");
    try testing.expect(!c.eql(d));
}

test "dynamic equality" {
    const a = try local_name.LocalName.fromSlice("my-tag");
    const b = try local_name.LocalName.fromSlice("my-tag");

    try testing.expect(a.eql(b));
}

test "one of" {
    const a = try local_name.LocalName.fromSlice("body");
    try testing.expect(a.oneOf(&.{ .body, .table, .tr }));
}
