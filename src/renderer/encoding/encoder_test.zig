const std = @import("std");
const testing = std.testing;
const Encoder = @import("Encoder.zig");
const Encoding = @import("encoding.zig").Encoding;
const IoQueue = @import("queue.zig").IoQueue;

fn expectEncode(encoding: Encoding, codepoints: []const u21, expected: []const u8) !void {
    var encoder = Encoder.init(encoding);
    var input = try IoQueue(u21).fromSlice(testing.allocator, codepoints);
    defer input.deinit(testing.allocator);
    var output: IoQueue(u8) = .{};
    defer output.deinit(testing.allocator);

    try testing.expectEqual(@as(?u21, null), try encoder.encodeOrFail(testing.allocator, &input, &output));
    try testing.expectEqualStrings(expected, try output.readAll());
}

test "encoding Encoder: encode code points" {
    try expectEncode(.utf8, &.{ 'A', 0xE9, 0x4E2D, 0x1F600 }, "Aé中😀");
    try expectEncode(.windows1252, &.{ 'A', 0xE9, 0x20AC }, "A\xE9\x80");
    try expectEncode(.shift_jis, &.{0x2261}, "\x81\xDF");
    try expectEncode(.iso2022jp, &.{ 0xA5, 0xA5 }, "\x1B(J\\\\\x1B(B");
}
