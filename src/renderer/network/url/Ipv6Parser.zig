//! https://url.spec.whatwg.org/#concept-ipv6-parser
const Ipv6Parser = @This();
const std = @import("std");
const ascii = @import("../../utils/ascii.zig");
const ErrorAdapter = @import("ErrorAdapter.zig");

/// The address, indices, and compression position used by the IPv6 steps.
input: []const u8,
adapter: ?ErrorAdapter,
address: [8]u16 = @splat(0),
piece_index: usize = 0,
compress: ?usize = null,
pointer: usize = 0,

/// Parses IPv6, including a final IPv4 address such as `::ffff:192.0.2.1`.
/// Returns the address as 16 bytes in network order.
/// https://url.spec.whatwg.org/#concept-ipv6-parser
pub fn parse(self: *Ipv6Parser) ![16]u8 {
    if (std.mem.startsWith(u8, self.input, ":")) {
        if (!std.mem.startsWith(u8, self.input, "::"))
            return ErrorAdapter.fail(self.adapter, .IPv6InvalidCompression);
        self.pointer = 2;
        self.piece_index = 1;
        self.compress = self.piece_index;
    }
    while (self.pointer < self.input.len) {
        if (self.piece_index == self.address.len)
            return ErrorAdapter.fail(self.adapter, .IPv6TooManyPieces);
        if (self.input[self.pointer] == ':') {
            if (self.compress != null)
                return ErrorAdapter.fail(self.adapter, .IPv6MultipleCompression);
            self.pointer += 1;
            self.piece_index += 1;
            self.compress = self.piece_index;
            continue;
        }
        if (try self.readPiece()) break;
    }
    try self.expand();
    var bytes: [16]u8 = undefined;
    for (self.address, 0..) |piece, i| {
        bytes[i * 2] = @intCast(piece >> 8);
        bytes[i * 2 + 1] = @truncate(piece);
    }
    return bytes;
}

/// Reads one hexadecimal piece. True means an IPv4 tail finished the input.
pub fn readPiece(self: *Ipv6Parser) !bool {
    const start = self.pointer;
    var value: u16 = 0;
    while (self.pointer - start < 4 and self.pointer < self.input.len and
        ascii.isAsciiHexDigit(self.input[self.pointer]))
    {
        value = value * 16 + ascii.toHexDigit(u16, self.input[self.pointer]);
        self.pointer += 1;
    }
    const length = self.pointer - start;
    if (self.pointer < self.input.len and self.input[self.pointer] == '.') {
        if (length == 0) return ErrorAdapter.fail(self.adapter, .IPv4InIPv6InvalidCodePoint);
        self.pointer = start;
        if (self.piece_index > 6) return ErrorAdapter.fail(self.adapter, .IPv4InIPv6TooManyPieces);
        try self.readIPv4();
        return true;
    }
    if (self.pointer < self.input.len) {
        if (self.input[self.pointer] != ':')
            return ErrorAdapter.fail(self.adapter, .IPv6InvalidCodePoint);
        self.pointer += 1;
        if (self.pointer == self.input.len)
            return ErrorAdapter.fail(self.adapter, .IPv6InvalidCodePoint);
    }
    if (length > 1 and self.input[start] == '0')
        ErrorAdapter.report(self.adapter, .IPv6PieceLeadingZero);
    self.address[self.piece_index] = value;
    self.piece_index += 1;
    return false;
}

/// Reads the four decimal parts in spec 6.5.
pub fn readIPv4(self: *Ipv6Parser) !void {
    var numbers_seen: usize = 0;
    while (self.pointer < self.input.len) {
        if (numbers_seen > 0) {
            if (self.input[self.pointer] != '.' or numbers_seen >= 4)
                return ErrorAdapter.fail(self.adapter, .IPv4InIPv6InvalidCodePoint);
            self.pointer += 1;
        }
        const value = try self.readDecimal();
        self.address[self.piece_index] = self.address[self.piece_index] * 0x100 + value;
        numbers_seen += 1;
        if (numbers_seen == 2 or numbers_seen == 4) self.piece_index += 1;
    }
    if (numbers_seen != 4) return ErrorAdapter.fail(self.adapter, .IPv4InIPv6TooFewParts);
}

/// Reads one IPv4 part, rejecting leading zeros and values above 255.
pub fn readDecimal(self: *Ipv6Parser) !u16 {
    if (self.pointer == self.input.len or !ascii.isAsciiDigit(self.input[self.pointer]))
        return ErrorAdapter.fail(self.adapter, .IPv4InIPv6InvalidCodePoint);
    var value: ?u16 = null;
    while (self.pointer < self.input.len and ascii.isAsciiDigit(self.input[self.pointer])) {
        const digit = self.input[self.pointer] - '0';
        if (value) |previous| {
            if (previous == 0) return ErrorAdapter.fail(self.adapter, .IPv4InIPv6InvalidCodePoint);
            value = previous * 10 + digit;
        } else value = digit;
        if (value.? > 255) return ErrorAdapter.fail(self.adapter, .IPv4InIPv6OutOfRangePart);
        self.pointer += 1;
    }
    return value.?;
}

/// Expands the compressed zero pieces, or checks that all eight are present.
pub fn expand(self: *Ipv6Parser) !void {
    if (self.compress) |compress| {
        var swaps = self.piece_index - compress;
        self.piece_index = self.address.len - 1;
        while (self.piece_index != 0 and swaps > 0) {
            std.mem.swap(u16, &self.address[self.piece_index], &self.address[compress + swaps - 1]);
            self.piece_index -= 1;
            swaps -= 1;
        }
    } else if (self.piece_index != self.address.len) {
        return ErrorAdapter.fail(self.adapter, .IPv6TooFewPieces);
    }
}

/// Formats 16 address bytes as an IPv6 host.
/// https://url.spec.whatwg.org/#concept-ipv6-serializer
///
/// Some examples:
/// `2001:0db8:0000:0000:0000:0000:0000:0001` → `[2001:db8::1]`
/// `0000:0000:0000:0000:0000:0000:0000:0000` → `[::]`
/// `0001:0000:0000:0002:0000:0000:0003:0004` → `[1::2:0:0:3:4]`
pub fn serialize(self: *const Ipv6Parser, allocator: std.mem.Allocator) ![]u8 {
    const pieces = self.address;
    const run = longestZeroRun(&pieces);
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try output.append(allocator, '[');
    var i: usize = 0;
    while (i < pieces.len) {
        if (run.len > 1 and i == run.start) {
            try output.appendSlice(allocator, "::");
            i += run.len;
        } else {
            if (i != 0 and output.items[output.items.len - 1] != ':') try output.append(allocator, ':');
            var buffer: [4]u8 = undefined;
            try output.appendSlice(allocator, try std.fmt.bufPrint(&buffer, "{x}", .{pieces[i]}));
            i += 1;
        }
    }
    try output.append(allocator, ']');
    return output.toOwnedSlice(allocator);
}

fn longestZeroRun(pieces: *const [8]u16) struct { start: usize, len: usize } {
    var best: struct { start: usize, len: usize } = .{
        .start = 0,
        .len = 0,
    };
    var i: usize = 0;
    while (i < pieces.len) {
        if (pieces[i] != 0) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < pieces.len and pieces[i] == 0) : (i += 1) {}
        if (i - start > best.len) best = .{
            .start = start,
            .len = i - start,
        };
    }
    return .{
        .start = best.start,
        .len = best.len,
    };
}

test "network url ipv6: parse address" {
    const address: [16]u8 = .{ 0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 };
    var parser: Ipv6Parser = .{ .input = "2001:db8::1", .adapter = null };
    try std.testing.expectEqual(address, try parser.parse());

    const with_ipv4: [16]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 192, 0, 2, 1 };
    var ipv4_parser: Ipv6Parser = .{ .input = "::ffff:192.0.2.1", .adapter = null };
    try std.testing.expectEqual(with_ipv4, try ipv4_parser.parse());
}
