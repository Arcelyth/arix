//! Generates Bidi_Class lookup from DerivedBidiClass and PropertyValueAliases.
const std = @import("std");
const Aliases = std.StringHashMap([]const u8);

/// Arguments:
/// - args[1]: input `DerivedBidiClass.txt` file.
/// - args[2]: input `PropertyValueAliases.txt` file.
/// - args[3]: output Zig source file.
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4) return error.InvalidArguments;

    const content = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], allocator, .unlimited);
    const names = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], allocator, .unlimited);
    const aliases = try readAliases(allocator, names);
    const classes = try readClasses(allocator, content, aliases);

    var file = try std.Io.Dir.cwd().createFile(init.io, args[3], .{});
    defer file.close(init.io);
    var buffer: [4096]u8 = undefined;
    var output = file.writer(init.io, &buffer);
    try writeLookup(&output.interface, classes);

    try output.flush();
    return std.process.cleanExit(init.io);
}

fn readAliases(allocator: std.mem.Allocator, content: []const u8) !Aliases {
    var aliases = Aliases.init(allocator);
    errdefer aliases.deinit();
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, ';');
        if (!std.mem.eql(u8, trim(fields.next().?), "bc")) continue;
        const short = trim(fields.next() orelse return error.InvalidBidiData);
        const long = trim(fields.next() orelse return error.InvalidBidiData);
        try aliases.put(short, short);
        try aliases.put(long, short);
    }
    return aliases;
}

fn readClasses(allocator: std.mem.Allocator, content: []const u8, aliases: Aliases) ![][]const u8 {
    const classes = try allocator.alloc([]const u8, 0x110000);
    errdefer allocator.free(classes);
    @memset(classes, "");
    try applyFile(classes, content, aliases, true);
    try applyFile(classes, content, aliases, false);
    for (classes) |class| if (class.len == 0) return error.MissingBidiDefault;
    return classes;
}

/// Apply defaults first, then let explicit property records override them.
fn applyFile(
    classes: [][]const u8,
    content: []const u8,
    aliases: Aliases,
    defaults: bool,
) !void {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const record = if (defaults)
            if (std.mem.indexOf(u8, line, "# @missing:")) |i| line[i + "# @missing:".len ..] else continue
        else
            line[0 .. std.mem.indexOfScalar(u8, line, '#') orelse line.len];
        if (trim(record).len == 0) continue;
        try applyRecord(classes, record, aliases);
    }
}

fn applyRecord(classes: [][]const u8, record: []const u8, aliases: Aliases) !void {
    var fields = std.mem.splitScalar(u8, record, ';');
    var range = std.mem.splitSequence(u8, trim(fields.next().?), "..");
    const first = try std.fmt.parseInt(u21, trim(range.next().?), 16);
    const last = if (range.next()) |end|
        try std.fmt.parseInt(u21, trim(end), 16)
    else
        first;

    if (first > last or last >= classes.len) return error.InvalidBidiRange;
    const name = trim(fields.next() orelse return error.InvalidBidiData);
    const class = aliases.get(name) orelse return error.UnknownBidiClass;
    @memset(classes[first .. @as(usize, last) + 1], class);
}

fn writeLookup(writer: *std.Io.Writer, classes: []const []const u8) !void {
    try writer.writeAll(
        \\// Generated from Unicode 18.0.0 DerivedBidiClass.txt. DO NOT EDIT.
        \\// Source: https://www.unicode.org/Public/18.0.0/ucd/extracted/DerivedBidiClass.txt
        \\// Unicode data license: https://www.unicode.org/license.txt
        \\pub fn bidiClass(comptime Class: type, codepoint: u21) Class {
        \\    const ranges = [_]struct { first: u21, last: u21, class: Class }{
        \\
    );
    var first: usize = 0;
    while (first < classes.len) {
        var end = first + 1;
        while (end < classes.len and std.mem.eql(u8, classes[first], classes[end])) : (end += 1) {}
        try writer.print("        .{{ .first = 0x{X}, .last = 0x{X}, .class = .{s} }},\n", .{ first, end - 1, classes[first] });
        first = end;
    }
    try writer.writeAll(
        \\    };
        \\    var low: usize = 0;
        \\    var high = ranges.len;
        \\    while (low < high) {
        \\        const mid = low + (high - low) / 2;
        \\        const range = ranges[mid];
        \\        if (codepoint < range.first) high = mid
        \\        else if (codepoint > range.last) low = mid + 1
        \\        else return range.class;
        \\    }
        \\    unreachable; // The generated ranges cover U+0000 through U+10FFFF.
        \\}
        \\
    );
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r");
}
