//! CSSOM common serialization rules for UTF-8 strings.
const std = @import("std");
const ascii = @import("../../utils/ascii.zig");
const Writer = std.Io.Writer;

/// Writes text as a CSS identifier.
/// https://drafts.csswg.org/cssom/#serialize-an-identifier
pub fn identifier(writer: *Writer, text: []const u8) !void {
    try writeIdentifier(writer, text, false);
}

fn writeIdentifier(writer: *Writer, text: []const u8, lowercase: bool) !void {
    var chars = (try std.unicode.Utf8View.init(text)).iterator();
    var index: usize = 0;
    while (chars.nextCodepointSlice()) |bytes| : (index += 1) {
        const cp = std.unicode.utf8Decode(bytes) catch unreachable;
        const leading_digit = ascii.isAsciiDigit(cp) and (index == 0 or (index == 1 and text[0] == '-'));
        if (cp == 0) {
            try writer.writeAll("�");
        } else if (needsHexEscape(cp) or leading_digit) {
            try hexEscape(writer, cp);
        } else {
            if (!ascii.isCssIdent(cp) or (cp == '-' and text.len == 1)) try writer.writeByte('\\');
            if (lowercase and ascii.isAsciiUpperAlpha(cp))
                try writer.writeByte(std.ascii.toLower(@intCast(cp)))
            else
                try writer.writeAll(bytes);
        }
    }
}

fn needsHexEscape(cp: u21) bool {
    return (cp >= 1 and cp <= 0x1f) or cp == 0x7f;
}

// https://drafts.csswg.org/cssom/#escape-a-character-as-code-point
fn hexEscape(writer: *Writer, cp: u21) !void {
    try writer.print("\\{x} ", .{cp});
}

/// Writes text as a double-quoted CSS string.
/// https://drafts.csswg.org/cssom/#serialize-a-string
pub fn string(writer: *Writer, text: []const u8) !void {
    var chars = (try std.unicode.Utf8View.init(text)).iterator();
    try writer.writeByte('"');
    while (chars.nextCodepointSlice()) |bytes| {
        const cp = std.unicode.utf8Decode(bytes) catch unreachable;
        if (cp == 0) {
            try writer.writeAll("�");
        } else if (needsHexEscape(cp)) {
            try hexEscape(writer, cp);
        } else {
            if (cp == '"' or cp == '\\') try writer.writeByte('\\');
            try writer.writeAll(bytes);
        }
    }
    try writer.writeByte('"');
}

/// Writes a URL as url("…").
/// https://drafts.csswg.org/cssom/#serialize-a-url
pub fn url(writer: *Writer, value: []const u8) !void {
    try writer.writeAll("url(");
    try string(writer, value);
    try writer.writeByte(')');
}

/// Writes a local font family name as local("…").
/// https://drafts.csswg.org/cssom/#serialize-a-local
pub fn local(writer: *Writer, family: []const u8) !void {
    try writer.writeAll("local(");
    try string(writer, family);
    try writer.writeByte(')');
}

/// Writes a CSS function around its serialized arguments.
/// https://drafts.csswg.org/cssom/#css-serialize-a-function
pub fn function(writer: *Writer, name: []const u8, arguments: []const u8) !void {
    try writeIdentifier(writer, name, true);
    try writer.writeByte('(');
    try writer.writeAll(arguments);
    try writer.writeByte(')');
}

/// Joins serialized items with a comma and space, or a single space.
/// https://drafts.csswg.org/cssom/#serialize-a-comma-separated-list
/// https://drafts.csswg.org/cssom/#serialize-a-whitespace-separated-list
pub fn list(writer: *Writer, items: []const []const u8, separator: enum { comma, whitespace }) !void {
    for (items, 0..) |item, i| {
        if (i != 0) try writer.writeAll(if (separator == .comma) ", " else " ");
        try writer.writeAll(item);
    }
}

test "CSSOM serialize function arguments and lists" {
    var output: Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    const writer = &output.writer;
    try url(writer, "a\"b\n");
    try local(writer, "A\\B");
    try function(writer, "F×", "1");
    try list(writer, &.{ "a", "b" }, .comma);
    try list(writer, &.{ "c", "d" }, .whitespace);
    try std.testing.expectEqualStrings("url(\"a\\\"b\\a \")local(\"A\\\\B\")f\\×(1)a, bc d", output.written());
}
