//! Binary PPM (P6) format encoder.
const std = @import("std");

pub const Pixel = [3]u8;

pub fn encode(allocator: std.mem.Allocator, width: usize, height: usize, pixels: []const Pixel) ![]u8 {
    if (width == 0 or height == 0) return error.InvalidDimensions;
    if (try std.math.mul(usize, width, height) != pixels.len) return error.InvalidPixelCount;
    var buffer: [128]u8 = undefined;
    const header = try std.fmt.bufPrint(&buffer, "P6\n{d} {d}\n255\n", .{ width, height });
    const byte_len = try std.math.mul(usize, pixels.len, 3);
    const result = try allocator.alloc(u8, try std.math.add(usize, header.len, byte_len));
    @memcpy(result[0..header.len], header);
    @memcpy(result[header.len..], std.mem.sliceAsBytes(pixels));
    return result;
}
