//! Uncompressed 24-bit BMP encoder (BITMAPINFOHEADER, bottom-up BGR rows).
const std = @import("std");

pub const Pixel = [3]u8;
const header_size = 54;

/// Encodes top-down RGB pixels.
pub fn encode(allocator: std.mem.Allocator, width: usize, height: usize, pixels: []const Pixel) ![]u8 {
    const layout = try Layout.init(width, height);
    if (try std.math.mul(usize, width, height) != pixels.len) return error.InvalidPixelCount;
    const result = try allocator.alloc(u8, layout.file_size);
    @memset(result, 0);
    writeHeader(result[0..header_size], width, height, layout.file_size);
    writePixels(result[header_size..], width, height, layout.stride, pixels);

    return result;
}

const Layout = struct {
    stride: usize,
    file_size: u32,

    fn init(width: usize, height: usize) !Layout {
        if (width == 0 or height == 0 or width > std.math.maxInt(i32) or height > std.math.maxInt(i32))
            return error.InvalidDimensions;
        // Compute in u64 so oversized BMPs are rejected on both 32- and 64-bit hosts.
        const stride = (@as(u64, width) * 3 + 3) & ~@as(u64, 3);
        const file_size = std.math.cast(u32, header_size + stride * height) orelse return error.ImageTooLarge;
        return .{ .stride = @intCast(stride), .file_size = file_size };
    }
};

fn writeHeader(header: *[header_size]u8, width: usize, height: usize, file_size: u32) void {
    @memcpy(header[0..2], "BM");
    std.mem.writeInt(u32, header[2..6], file_size, .little);
    std.mem.writeInt(u32, header[10..14], header_size, .little);
    std.mem.writeInt(u32, header[14..18], 40, .little);
    std.mem.writeInt(i32, header[18..22], @intCast(width), .little);
    std.mem.writeInt(i32, header[22..26], @intCast(height), .little);
    std.mem.writeInt(u16, header[26..28], 1, .little);
    std.mem.writeInt(u16, header[28..30], 24, .little);
    // Compression, palette, resolution, and reserved fields remain zero.
    std.mem.writeInt(u32, header[34..38], file_size - header_size, .little);
}

fn writePixels(output: []u8, width: usize, height: usize, stride: usize, pixels: []const Pixel) void {
    for (0..height) |y| {
        const source = pixels[(height - 1 - y) * width ..][0..width];
        const row = output[y * stride ..][0..stride];
        for (source, 0..) |pixel, x| {
            @memcpy(row[x * 3 ..][0..3], &[_]u8{ pixel[2], pixel[1], pixel[0] });
        }
    }
}
