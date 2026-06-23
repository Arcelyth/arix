const std = @import("std");
const get_attr = @import("attr.zig").get_attr;

test "charset quoted" {
    const html = " charset=\"utf-8\">";
    var pos: usize = 0;
    const res = get_attr(html, &pos, html.len);
    try std.testing.expect(res[0] != null);
    const attr = res[0].?;
    try std.testing.expectEqualStrings(
        "charset",
        attr.name,
    );

    try std.testing.expectEqualStrings(
        "utf-8",
        attr.value,
    );
}

test "charset single quoted" {
    const html = " charset='utf-8'>";
    var pos: usize = 0;
    const res = get_attr(html, &pos, html.len);
    const attr = res[0].?;

    try std.testing.expectEqualStrings(
        "charset",
        attr.name,
    );

    try std.testing.expectEqualStrings(
        "utf-8",
        attr.value,
    );
}

test "charset unquoted" {
    const html = " charset=utf-8>";

    var pos: usize = 0;
    const res = get_attr(html, &pos, html.len);
    const attr = res[0].?;

    try std.testing.expectEqualStrings(
        "charset",
        attr.name,
    );

    try std.testing.expectEqualStrings(
        "utf-8",
        attr.value,
    );
}

test "attribute without value" {
    const html = " disabled>";

    var pos: usize = 0;
    const res = get_attr(html, &pos, html.len);
    const attr = res[0].?;

    try std.testing.expectEqualStrings(
        "disabled",
        attr.name,
    );

    try std.testing.expectEqualStrings(
        "",
        attr.value,
    );
}

test "multiple attributes" {
    const html = " charset=\"utf-8\" content=\"text/html\">";
    var pos: usize = 0;
    const r1 = get_attr(html, &pos, html.len);

    try std.testing.expectEqualStrings(
        "charset",
        r1[0].?.name,
    );
    const r2 = get_attr(html, &pos, html.len);

    try std.testing.expectEqualStrings(
        "content",
        r2[0].?.name,
    );
}
