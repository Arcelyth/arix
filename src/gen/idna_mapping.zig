//! Generates the UTS #46 status and mapping lookup.
const std = @import("std");

const Status = enum {
    valid,
    ignored,
    mapped,
    deviation,
    disallowed,
};

const Range = struct {
    first: u21,
    last: u21,
    status: Status,
    mapping: []const u21,
};

/// Arguments:
/// - args[1]: input IdnaMappingTable.txt.
/// - args[2]: output Zig source file.
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.InvalidArguments;

    const content = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], allocator, .unlimited);
    const ranges = try readTable(allocator, content);
    var file = try std.Io.Dir.cwd().createFile(init.io, args[2], .{});
    defer file.close(init.io);
    var buffer: [4096]u8 = undefined;
    var output = file.writer(init.io, &buffer);

    try writeTable(&output.interface, ranges);
    try output.flush();
    return std.process.cleanExit(init.io);
}

/// Checks that records cover every Unicode code point in order.
fn readTable(allocator: std.mem.Allocator, content: []const u8) ![]const Range {
    var ranges: std.ArrayList(Range) = .empty;
    var next: usize = 0;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const record = trim(line[0 .. std.mem.indexOfScalar(u8, line, '#') orelse line.len]);
        if (record.len == 0) continue;
        const range = try readRecord(allocator, record);
        if (range.first != next or range.last < range.first or range.last > 0x10FFFF)
            return error.InvalidIdnaRange;
        next = @as(usize, range.last) + 1;
        try ranges.append(allocator, range);
    }
    if (next != 0x110000) return error.IncompleteIdnaTable;
    return ranges.toOwnedSlice(allocator);
}

fn readRecord(allocator: std.mem.Allocator, record: []const u8) !Range {
    var fields = std.mem.splitScalar(u8, record, ';');
    var bounds = std.mem.splitSequence(u8, trim(fields.next().?), "..");
    const first = try std.fmt.parseInt(u21, bounds.next().?, 16);
    const last = if (bounds.next()) |value| try std.fmt.parseInt(u21, value, 16) else first;
    if (bounds.next() != null) return error.InvalidIdnaRange;
    const status = std.meta.stringToEnum(Status, trim(fields.next() orelse return error.MissingIdnaStatus)) orelse
        return error.UnknownIdnaStatus;
    const mapping = try readMapping(allocator, fields.next() orelse "");
    if ((status == .mapped and mapping.len == 0) or
        (status != .mapped and status != .deviation and mapping.len != 0))
        return error.InvalidIdnaMapping;

    return .{
        .first = first,
        .last = last,
        .status = status,
        .mapping = mapping,
    };
}

fn readMapping(allocator: std.mem.Allocator, text: []const u8) ![]const u21 {
    var mapping: std.ArrayList(u21) = .empty;
    var values = std.mem.tokenizeAny(u8, text, " \t\r");
    while (values.next()) |value| {
        const cp = try std.fmt.parseInt(u21, value, 16);
        if (cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) return error.InvalidIdnaMapping;
        try mapping.append(allocator, cp);
    }
    return mapping.toOwnedSlice(allocator);
}

fn writeTable(writer: *std.Io.Writer, ranges: []const Range) !void {
    try writer.writeAll(
        \\// Generated from Unicode 18.0.0 IdnaMappingTable.txt. DO NOT EDIT.
        \\// Source: https://www.unicode.org/Public/18.0.0/idna/IdnaMappingTable.txt
        \\// Unicode data license: https://www.unicode.org/license.txt
        \\pub const Status = enum {
        \\
    );
    inline for (std.meta.tags(Status)) |status|
        try writer.print("    {s},\n", .{@tagName(status)});
    try writer.writeAll(
        \\};
        \\/// Mapping-table status and replacement code points.
        \\pub const Mapping = struct { status: Status, mapping: []const u21 };
        \\const Range = struct { first: u21, last: u21, value: Mapping };
        \\const ranges = [_]Range{
        \\
    );
    for (ranges) |range| try writeRange(writer, range);
    try writer.writeAll(
        \\};
        \\/// Looks up U+0000 through U+10FFFF, including surrogate code points.
        \\pub fn lookup(codepoint: u21) Mapping {
        \\    var low: usize = 0;
        \\    var high = ranges.len;
        \\    while (low < high) {
        \\        const mid = low + (high - low) / 2;
        \\        const range = ranges[mid];
        \\        if (codepoint < range.first) high = mid
        \\        else if (codepoint > range.last) low = mid + 1
        \\        else return range.value;
        \\    }
        \\    unreachable; // readTable checks full Unicode coverage.
        \\}
        \\
    );
}

fn writeRange(writer: *std.Io.Writer, range: Range) !void {
    try writer.print(
        "    .{{ .first = 0x{X}, .last = 0x{X}, .value = .{{ .status = .{s}, .mapping = &.{{",
        .{
            range.first,
            range.last,
            @tagName(range.status),
        },
    );
    for (range.mapping) |cp| try writer.print("0x{X},", .{cp});
    try writer.writeAll("} } },\n");
}

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r");
}
