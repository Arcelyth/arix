//! Generates the paired-bracket properties needed by UAX #9 BD14–BD16.
const std = @import("std");

/// Arguments:
/// - args[1]: input text file.
/// - args[2]: output Zig source file.
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.InvalidArguments;

    const content = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], allocator, .unlimited);
    var file = try std.Io.Dir.cwd().createFile(init.io, args[2], .{});
    defer file.close(init.io);
    var buffer: [4096]u8 = undefined;
    var output = file.writer(init.io, &buffer);

    const writer = &output.interface;
    try writer.writeAll(
        \\// Generated from Unicode 18.0.0 BidiBrackets.txt. DO NOT EDIT.
        \\// Source: https://www.unicode.org/Public/18.0.0/ucd/BidiBrackets.txt
        \\// Unicode data license: https://www.unicode.org/license.txt
        \\pub const Bracket = struct { codepoint: u21, pair: u21, is_open: bool };
        \\pub const entries = [_]Bracket{
        \\
    );
    try writeEntries(writer, content);
    try writer.writeAll("};\n");
    try output.flush();
    return std.process.cleanExit(init.io);
}

fn writeEntries(writer: *std.Io.Writer, content: []const u8) !void {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const record = std.mem.trim(
            u8,
            line[0 .. std.mem.indexOfScalar(u8, line, '#') orelse line.len],
            " \t\r",
        );
        if (record.len == 0) continue;
        var fields = std.mem.splitScalar(u8, record, ';');
        const codepoint = fields.next() orelse return error.InvalidBracketData;
        const pair = fields.next() orelse return error.InvalidBracketData;

        const kind = std.mem.trim(u8, fields.next() orelse return error.InvalidBracketData, " \t");
        if (std.mem.eql(u8, kind, "n")) continue;
        if (!std.mem.eql(u8, kind, "o") and !std.mem.eql(u8, kind, "c")) return error.InvalidBracketData;
        try writer.print("    .{{ .codepoint = 0x{X}, .pair = 0x{X}, .is_open = {} }},\n", .{
            try std.fmt.parseInt(u21, std.mem.trim(u8, codepoint, " \t"), 16),
            try std.fmt.parseInt(u21, std.mem.trim(u8, pair, " \t"), 16),
            std.mem.eql(u8, kind, "o"),
        });
    }
}
