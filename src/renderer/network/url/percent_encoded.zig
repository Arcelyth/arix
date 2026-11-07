//! https://url.spec.whatwg.org/#percent-encoded-bytes
const std = @import("std");
const ascii = @import("../../utils/ascii.zig");
const encodings = @import("../../encoding/encoding.zig");
const Encoding = encodings.Encoding;
const IoQueue = @import("../../encoding/queue.zig").IoQueue;

/// The percent-encode set.
/// https://url.spec.whatwg.org/#percent-encode-set
pub const Set = enum {
    c0_control,
    fragment,
    query,
    special_query,
    path,
    userinfo,
    component,
    /// https://url.spec.whatwg.org/#application-x-www-form-urlencoded-percent-encode-set
    form_urlencoded,

    /// Checks whether the byte belongs to the chosen percent-encode set.
    /// - true: encode it as %HH.
    /// - false: append it unchanged.
    ///
    /// For example, contains(.userinfo, '@') returns true, so @ becomes %40.
    fn contains(self: Set, byte: u8) bool {
        if (byte <= 0x1f or byte > 0x7e) return true;
        return switch (self) {
            .c0_control => false,
            .fragment => switch (byte) {
                ' ', '"', '<', '>', '`' => true,
                else => false,
            },
            .query => switch (byte) {
                ' ', '"', '#', '<', '>' => true,
                else => false,
            },
            .special_query => contains(.query, byte) or byte == '\'',
            .path => contains(.query, byte) or switch (byte) {
                '?', '^', '`', '{', '}' => true,
                else => false,
            },
            .userinfo => contains(.path, byte) or switch (byte) {
                '/', ':', ';', '=', '@', '[', '\\', ']', '|' => true,
                else => false,
            },
            .form_urlencoded => contains(.component, byte) or switch (byte) {
                '!', '\'', '(', ')', '~' => true,
                else => false,
            },
            .component => contains(.userinfo, byte) or switch (byte) {
                '$'...'&', '+', ',' => true,
                else => false,
            },
        };
    }
};

pub fn appendByte(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    byte: u8,
    set: Set,
) !void {
    var bytes: [3]u8 = undefined;
    const length = encodeByte(byte, set, &bytes);
    try output.appendSlice(allocator, bytes[0..length]);
}

// One byte becomes either itself or a three-byte %HH escape.
fn encodeByte(byte: u8, set: Set, output: *[3]u8) usize {
    if (!set.contains(byte)) {
        output[0] = byte;
        return 1;
    }
    const hex = "0123456789ABCDEF";
    output.* = .{ '%', hex[byte >> 4], hex[byte & 15] };
    return 3;
}

pub fn append(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    cp: u21,
    set: Set,
) !void {
    var bytes: [12]u8 = undefined;
    try output.appendSlice(allocator, try encodeCodepoint(cp, set, &bytes));
}

/// Writes one UTF-8 percent-encoded code point to buffer.
pub fn encodeCodepoint(cp: u21, set: Set, buffer: *[12]u8) ![]const u8 {
    var bytes: [4]u8 = undefined;
    const length = try std.unicode.utf8Encode(cp, &bytes);
    var end: usize = 0;
    for (bytes[0..length]) |byte| end += encodeByte(byte, set, buffer[end..][0..3]);
    return buffer[0..end];
}

/// Converts % followed by two hex digits into a byte in `input`.
/// For example, %40 becomes byte 0x40 (@).
/// https://url.spec.whatwg.org/#percent-decode
pub fn decode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const output = try allocator.alloc(u8, input.len);
    errdefer allocator.free(output);
    var length: usize = 0;
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        if (isEncodedByte(input[i..])) {
            output[length] = @as(u8, ascii.toHexDigit(u8, input[i + 1])) * 16 + ascii.toHexDigit(u8, input[i + 2]);
            i += 2;
        } else output[length] = input[i];
        length += 1;
    }
    return allocator.realloc(output, length);
}

/// Returns whether input starts with a percent-encoded byte, such as "%2F".
pub fn isEncodedByte(input: []const u8) bool {
    return input.len >= 3 and input[0] == '%' and
        ascii.isAsciiHexDigit(input[1]) and ascii.isAsciiHexDigit(input[2]);
}

/// Encodes text with one encoder instance and appends percent-encoded bytes.
/// Unencodable code points become percent-encoded decimal character references.
/// https://url.spec.whatwg.org/#string-percent-encode-after-encoding
pub fn percentEncodeAfterEncoding(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    text: []const u8,
    encoding: Encoding,
    set: Set,
) !void {
    std.debug.assert(encoding == .utf8 or set == .special_query or set == .form_urlencoded);

    var encoder = encodings.getEncoder(encoding);
    var input: IoQueue(u21) = .{};
    defer input.deinit(allocator);
    var chars = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (chars.nextCodepoint()) |cp| try input.push(allocator, cp);
    try input.push(allocator, null);

    var potential_error: ?u21 = 0;
    while (potential_error != null) {
        var encoded: IoQueue(u8) = .{};
        defer encoded.deinit(allocator);
        potential_error = try encoder.encodeOrFail(allocator, &input, &encoded);
        try appendEncodedBytes(allocator, output, try encoded.readAll(), set);
        if (potential_error) |cp| {
            try output.appendSlice(allocator, "%26%23");
            var buffer: [7]u8 = undefined;
            try output.appendSlice(allocator, try std.fmt.bufPrint(&buffer, "{d}", .{cp}));
            try output.appendSlice(allocator, "%3B");
        }
    }
}

/// Form encoding turns spaces into `+`; other bytes use the selected set.
pub fn appendEncodedBytes(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    bytes: []const u8,
    set: Set,
) !void {
    for (bytes) |byte| {
        if (set == .form_urlencoded and byte == 0x20)
            try output.append(allocator, '+')
        else
            try appendByte(allocator, output, byte, set);
    }
}
