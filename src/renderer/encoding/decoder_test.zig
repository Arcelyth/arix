const std = @import("std");
const testing = std.testing;
const Decoder = @import("Decoder.zig");
const encoding = @import("encoding.zig");
const Encoding = encoding.Encoding;
const IoQueue = @import("queue.zig").IoQueue;

// Exercise every first-chunk boundary, including byte-at-a-time input and EOF
// supplied separately. No BOM removal: these tests target the codec handlers.
fn expectDecode(enc: Encoding, bytes: []const u8, expected: []const u21) !void {
    for (1..bytes.len + 2) |chunk_size| {
        var decoder = Decoder.init(enc);
        var input: IoQueue(u8) = .{};
        defer input.deinit(testing.allocator);
        var output: IoQueue(u21) = .{};
        defer output.deinit(testing.allocator);

        var pos: usize = 0;
        while (pos < bytes.len and !output.ended) {
            const end = @min(pos + chunk_size, bytes.len);
            try input.pushSlice(testing.allocator, bytes[pos..end]);
            const result = decoder.processQueue(testing.allocator, &input, &output, .replacement);
            if (result) |status| {
                try testing.expectEqual(Decoder.ProcessResult.finished, status);
            } else |err| {
                try testing.expectEqual(error.NeedInput, err);
                try testing.expect(!output.ended);
            }
            pos = end;
        }
        if (!output.ended) {
            try input.push(testing.allocator, null);
            try testing.expectEqual(.finished, try decoder.processQueue(testing.allocator, &input, &output, .replacement));
        }
        try testing.expect(output.ended);
        try testing.expectEqualSlices(u21, expected, try output.readAll());
    }
}

test "encoding Decoder: UTF-8 scalars and malformed sequences" {
    try expectDecode(.utf8, "Aé中😀", &.{ 'A', 0xE9, 0x4E2D, 0x1F600 });
    try expectDecode(.utf8, "\x00\x7F\xC2\x80\xDF\xBF\xE0\xA0\x80\xEF\xBF\xBF\xF0\x90\x80\x80\xF4\x8F\xBF\xBF", &.{ 0, 0x7F, 0x80, 0x7FF, 0x800, 0xFFFF, 0x10000, 0x10FFFF });
    try expectDecode(.utf8, "\xE2\x82<", &.{ 0xFFFD, '<' });
    try expectDecode(.utf8, "\xE0\x80\x80", &.{ 0xFFFD, 0xFFFD, 0xFFFD });
    try expectDecode(.utf8, "\xED\xA0\x80", &.{ 0xFFFD, 0xFFFD, 0xFFFD });
    try expectDecode(.utf8, "\xF4\x90\x80\x80", &.{ 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD });
    try expectDecode(.utf8, "\xC0\xAF\xFF", &.{ 0xFFFD, 0xFFFD, 0xFFFD });
    try expectDecode(.utf8, "\xF0\x9F\x92", &.{0xFFFD});
}

test "encoding Decoder: every single-byte index" {
    const cases = .{
        .{ Encoding.ibm866, 0x0410, 0x00A0 },
        .{ Encoding.iso88592, 0x0080, 0x02D9 },
        .{ Encoding.iso88593, 0x0080, 0x02D9 },
        .{ Encoding.iso88594, 0x0080, 0x02D9 },
        .{ Encoding.iso88595, 0x0080, 0x045F },
        .{ Encoding.iso88596, 0x0080, 0xFFFD },
        .{ Encoding.iso88597, 0x0080, 0xFFFD },
        .{ Encoding.iso88598, 0x0080, 0xFFFD },
        .{ Encoding.iso88598_i, 0x0080, 0xFFFD },
        .{ Encoding.iso885910, 0x0080, 0x0138 },
        .{ Encoding.iso885913, 0x0080, 0x2019 },
        .{ Encoding.iso885914, 0x0080, 0x00FF },
        .{ Encoding.iso885915, 0x0080, 0x00FF },
        .{ Encoding.iso885916, 0x0080, 0x00FF },
        .{ Encoding.koi8r, 0x2500, 0x042A },
        .{ Encoding.koi8u, 0x2500, 0x042A },
        .{ Encoding.macintosh, 0x00C4, 0x02C7 },
        .{ Encoding.windows874, 0x20AC, 0xFFFD },
        .{ Encoding.windows1250, 0x20AC, 0x02D9 },
        .{ Encoding.windows1251, 0x0402, 0x044F },
        .{ Encoding.windows1252, 0x20AC, 0x00FF },
        .{ Encoding.windows1253, 0x20AC, 0xFFFD },
        .{ Encoding.windows1254, 0x20AC, 0x00FF },
        .{ Encoding.windows1255, 0x20AC, 0xFFFD },
        .{ Encoding.windows1256, 0x20AC, 0x06D2 },
        .{ Encoding.windows1257, 0x20AC, 0x02D9 },
        .{ Encoding.windows1258, 0x20AC, 0x00FF },
        .{ Encoding.x_mac_cyrillic, 0x0410, 0x20AC },
    };
    inline for (cases) |case| try expectDecode(case[0], "\x00A\x7F\x80\xFF", &.{ 0, 'A', 0x7F, case[1], case[2] });
}

fn gb18030Bytes(pointer: u32) [4]u8 {
    return .{
        @intCast(pointer / 12600 + 0x81),
        @intCast(pointer / 1260 % 10 + 0x30),
        @intCast(pointer / 10 % 126 + 0x81),
        @intCast(pointer % 10 + 0x30),
    };
}

test "encoding Decoder: GBK and gb18030" {
    for ([_]Encoding{ .gbk, .gb18030 }) |enc| {
        try expectDecode(enc, "\xD6\xD0\x80\x81\x30\x81\x30", &.{ 0x4E2D, 0x20AC, 0x80 });
        try expectDecode(enc, &gb18030Bytes(7457), &.{0xE7C7});
        try expectDecode(enc, &gb18030Bytes(39419), &.{0xFFFF});
        try expectDecode(enc, &gb18030Bytes(189000), &.{0x10000});
        try expectDecode(enc, &gb18030Bytes(1237575), &.{0x10FFFF});
        for ([_]u32{ 39420, 188999, 1237576 }) |pointer| try expectDecode(enc, &gb18030Bytes(pointer), &.{0xFFFD});
        try expectDecode(enc, "\x81\x30 ", &.{ 0xFFFD, '0', ' ' });
        try expectDecode(enc, "\x81\x30\x81 ", &.{ 0xFFFD, '0', 0xFFFD, ' ' });
        try expectDecode(enc, "\x81<\xFF", &.{ 0xFFFD, '<', 0xFFFD });
        for (1..4) |len| try expectDecode(enc, "\x81\x30\x81"[0..len], &.{0xFFFD});
    }
}

test "encoding Decoder: Big5" {
    try expectDecode(.big5, "\xA4\x40\x88\x62\x88\x64\x88\xA3\x88\xA5", &.{ 0x4E00, 0xCA, 0x304, 0xCA, 0x30C, 0xEA, 0x304, 0xEA, 0x30C });
    try expectDecode(.big5, "\x81\x40", &.{ 0xFFFD, '@' }); // Unmapped pair restores its ASCII trail.
    try expectDecode(.big5, "\xA4<\x80\xFF\xA4", &.{ 0xFFFD, '<', 0xFFFD, 0xFFFD, 0xFFFD });
}

test "encoding Decoder: EUC-JP JIS0208, JIS0212 and halfwidth katakana" {
    try expectDecode(.eucjp, "\xA4\xA2\x8E\xB1\x8F\xA2\xAF", &.{ 0x3042, 0xFF71, 0x02D8 });
    try expectDecode(.eucjp, "\x8F\xA2<\xA4\xA2", &.{ 0xFFFD, '<', 0x3042 });
    try expectDecode(.eucjp, "\x8E<\x80\xFF", &.{ 0xFFFD, '<', 0xFFFD, 0xFFFD });
    try expectDecode(.eucjp, "\x8F", &.{0xFFFD});
    try expectDecode(.eucjp, "\x8F\xA2", &.{0xFFFD});
}

test "encoding Decoder: ISO-2022-JP states, escapes and EOF recovery" {
    try expectDecode(.iso2022jp, "A\x1B$B$\"\x1B(BA", &.{ 'A', 0x3042, 'A' });
    try expectDecode(.iso2022jp, "\x1B(J\\~\x1B(I!", &.{ 0xA5, 0x203E, 0xFF61 });
    try expectDecode(.iso2022jp, "\x1B$@$\"", &.{0x3042});
    try expectDecode(.iso2022jp, "\x1B(B\x1B(B", &.{0xFFFD});
    try expectDecode(.iso2022jp, "\x1B(X", &.{ 0xFFFD, '(', 'X' });
    try expectDecode(.iso2022jp, "\x1B", &.{0xFFFD});
    try expectDecode(.iso2022jp, "\x1B$", &.{ 0xFFFD, '$' });
    try expectDecode(.iso2022jp, "\x1B$B$", &.{0xFFFD});
    try expectDecode(.iso2022jp, "\x1B$B$\x1B(BA", &.{ 0xFFFD, 'A' });
    try expectDecode(.iso2022jp, "\x0E\x0F\x80", &.{ 0xFFFD, 0xFFFD, 0xFFFD });
    try expectDecode(.iso2022jp, "\x1B(I \x1B$B $\x00", &.{ 0xFFFD, 0xFFFD, 0xFFFD });
}

test "encoding Decoder: Shift_JIS" {
    try expectDecode(.shift_jis, "\x82\xA0\x80\xA1\xF0\x40\xF9\xFC", &.{ 0x3042, 0x80, 0xFF61, 0xE000, 0xE757 });
    try expectDecode(.shift_jis, "\x82\"\xFF\x82", &.{ 0xFFFD, '"', 0xFFFD, 0xFFFD });
}
