const std = @import("std");
const ascii = @import("../../utils/ascii.zig");
const Input = @import("Input.zig");
const Url = @import("Url.zig");

pub fn isWindowsDriveLetter(text: []const u8) bool {
    return text.len == 2 and ascii.isAsciiAlpha(text[0]) and (text[1] == ':' or text[1] == '|');
}

pub fn isSingleDot(text: []const u8) bool {
    return std.mem.eql(u8, text, ".") or std.ascii.eqlIgnoreCase(text, "%2e");
}

pub fn isDoubleDot(text: []const u8) bool {
    return std.mem.eql(u8, text, "..") or std.ascii.eqlIgnoreCase(text, ".%2e") or
        std.ascii.eqlIgnoreCase(text, "%2e.") or std.ascii.eqlIgnoreCase(text, "%2e%2e");
}

/// Removes the last path segment from the `output`.
/// If `file` is true, preserves a Windows drive-letter root (e.g. `C:`).
pub fn shorten(output: *std.ArrayList(u8), parsed: *Url.Parsed, opaque_path: bool) void {
    std.debug.assert(!opaque_path);

    const text = parsed.path.slice(output.items);
    if (std.mem.eql(u8, parsed.scheme.slice(output.items), "file") and
        text.len == 3 and
        isWindowsDriveLetter(text[1..]) and
        text[2] == ':')
        return;
    const slash = std.mem.lastIndexOfScalar(u8, text, '/') orelse return;
    const removed = parsed.path.len - slash;
    const start = parsed.path.begin + slash;
    const new_end = output.items.len - removed;
    std.mem.copyForwards(u8, output.items[start..new_end], output.items[parsed.path.end()..]);
    output.items.len = new_end;
    parsed.path.len = slash;
    if (parsed.query) |*query| query.begin -= removed;
    if (parsed.fragment) |*fragment| fragment.begin -= removed;
}

/// A Windows drive letter consists of an ASCII alphabetic character
/// followed by ':' or '|'. It must be followed by EOF, '/', '\\', '?', or '#'.
pub fn startsWithWindowsDriveLetter(input: *const Input) bool {
    var remaining = input.*;
    const first = remaining.next() orelse return false;
    const second = remaining.next() orelse return false;
    if (!ascii.isAsciiAlpha(first) or (second != ':' and second != '|')) return false;
    return switch (remaining.next() orelse return true) {
        '/', '\\', '?', '#' => true,
        else => false,
    };
}
