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
