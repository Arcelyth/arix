const std = @import("std");
const ErrorAdapter = @import("ErrorAdapter.zig");

pub const Ipv4Number = struct {
    /// Null means the number exceeds the 32-bit IPv4 address range.
    value: ?u32 = 0,
    validation_error: bool = false,
};

/// Parses an IPv4 number. Invalid digits or empty input return null.
/// The result records the spec's non-decimal validation flag.
/// https://url.spec.whatwg.org/#ipv4-number-parser
pub fn number(input: []const u8) ?Ipv4Number {
    if (input.len == 0) return null;
    var text = input;
    var radix: u8 = 10;
    var result: Ipv4Number = .{};
    if (text.len >= 2 and text[0] == '0') {
        result.validation_error = true;
        if (text[1] == 'x' or text[1] == 'X') {
            text = text[2..];
            radix = 16;
        } else {
            text = text[1..];
            radix = 8;
        }
    }
    for (text) |byte| {
        const digit = std.fmt.charToDigit(byte, radix) catch return null;
        if (result.value) |value|
            result.value = std.math.cast(u32, @as(u64, value) * radix + digit);
    }
    return result;
}

/// Parses IPv4 and reports validation errors.
/// https://url.spec.whatwg.org/#concept-ipv4-parser
pub fn parse(input: []const u8, adapter: ?ErrorAdapter) ![4]u8 {
    var text = input;
    var count = std.mem.count(u8, input, ".") + 1;
    // Check if the last item in parts is an empty string.
    if (std.mem.endsWith(u8, input, ".")) {
        ErrorAdapter.report(adapter, .IPv4EmptyPart);
        if (count > 1) {
            text = input[0 .. input.len - 1];
            count -= 1;
        }
    }
    if (count < 4) ErrorAdapter.report(adapter, .IPv4TooFewParts);
    if (count > 4) return ErrorAdapter.fail(adapter, .IPv4TooManyParts);
    var numbers: [4]Ipv4Number = undefined;
    var parts = std.mem.splitScalar(u8, text, '.');
    for (numbers[0..count]) |*part| {
        part.* = number(parts.next().?) orelse return ErrorAdapter.fail(adapter, .IPv4NonNumericPart);
        if (part.validation_error) ErrorAdapter.report(adapter, .IPv4NonDecimalPart);
    }
    try checkRanges(numbers[0..count], adapter);
    var address = numbers[count - 1].value.?;
    for (numbers[0 .. count - 1], 0..) |part, i|
        address += part.value.? << @as(u5, @intCast(8 * (3 - i)));
    return .{
        @truncate(address >> 24),
        @truncate(address >> 16),
        @truncate(address >> 8),
        @truncate(address),
    };
}

/// Checks parts after all number parsing and non-decimal reports are complete.
fn checkRanges(numbers: []const Ipv4Number, adapter: ?ErrorAdapter) !void {
    for (numbers) |part| {
        if (part.value == null or part.value.? > 255) {
            ErrorAdapter.report(adapter, .IPv4OutOfRangePart);
            break;
        }
    }
    for (numbers[0 .. numbers.len - 1]) |part|
        if (part.value == null or part.value.? > 255) return error.IPv4OutOfRangePart;
    const last = numbers[numbers.len - 1].value orelse return error.IPv4OutOfRangePart;
    const limit = @as(u64, 1) << @as(u6, @intCast(8 * (5 - numbers.len)));
    if (last >= limit) return error.IPv4OutOfRangePart;
}

pub fn serialize(allocator: std.mem.Allocator, address: [4]u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d}.{d}.{d}.{d}", .{ address[0], address[1], address[2], address[3] });
}

test "network url ipv4: parse address" {
    const expected: [4]u8 = .{ 127, 0, 0, 1 };
    try std.testing.expectEqual(expected, try parse("127.0.0.1", null));
    try std.testing.expectEqual(expected, try parse("127.1", null));
    try std.testing.expectEqual(expected, try parse("0x7f.0.0.1", null));
}
