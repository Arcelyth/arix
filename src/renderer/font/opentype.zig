const std = @import("std");

/// The OS/2 fields used for static face matching.
pub const Classification = struct {
    weight: f64,
    width: f64,
    italic: bool,
    oblique: bool,
};

pub fn classification(bytes: []const u8) ?Classification {
    // fsSelection ends at byte 64 in every OS/2 version.
    if (bytes.len < 64) return null;
    const weight = readU16(bytes, 4);
    const width_class = readU16(bytes, 6);
    if (weight < 1 or weight > 1000 or width_class < 1 or width_class > 9) return null;
    const selection = readU16(bytes, 62);
    const widths = [_]f64{ 50, 62.5, 75, 87.5, 100, 112.5, 125, 150, 200 };
    return .{
        .weight = @floatFromInt(weight),
        .width = widths[width_class - 1],
        .italic = selection & (1 << 0) != 0,
        .oblique = readU16(bytes, 0) >= 4 and selection & (1 << 9) != 0,
    };
}

/// OpenType post.italicAngle is counter-clockwise, whereas CSS uses clockwise.
pub fn slant(bytes: []const u8) ?f64 {
    if (bytes.len < 8) return null;
    const fixed = std.mem.readInt(i32, bytes[4..8], .big);
    return -@as(f64, @floatFromInt(fixed)) / 65536;
}

fn readU16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .big);
}
