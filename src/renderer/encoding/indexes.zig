//! Provides lookup helpers for the encoding index tables generated from
//! `indexes.json`. Decoders map pointers to code points; encoders look up
//! pointers from code points.
const std = @import("std");
const Encoding = @import("encoding.zig").Encoding;
const data = @import("encoding_indexes");

pub const big5 = &data.big5;
pub const euc_kr = &data.euc_kr;
pub const gb18030 = &data.gb18030;
pub const jis0208 = &data.jis0208;
pub const jis0212 = &data.jis0212;
pub const iso_2022_jp_katakana = &data.iso_2022_jp_katakana;

/// https://encoding.spec.whatwg.org/#index-code-point
pub fn codePoint(index: []const u21, position: usize) ?u21 {
    if (position >= index.len or index[position] == 0) return null;
    return index[position];
}

/// https://encoding.spec.whatwg.org/#index-single-byte
pub fn singleByte(encoding: Encoding) *const [128]u21 {
    return switch (encoding) {
        .ibm866 => &data.ibm866,
        .iso88592 => &data.iso_8859_2,
        .iso88593 => &data.iso_8859_3,
        .iso88594 => &data.iso_8859_4,
        .iso88595 => &data.iso_8859_5,
        .iso88596 => &data.iso_8859_6,
        .iso88597 => &data.iso_8859_7,
        .iso88598, .iso88598_i => &data.iso_8859_8,
        .iso885910 => &data.iso_8859_10,
        .iso885913 => &data.iso_8859_13,
        .iso885914 => &data.iso_8859_14,
        .iso885915 => &data.iso_8859_15,
        .iso885916 => &data.iso_8859_16,
        .koi8r => &data.koi8_r,
        .koi8u => &data.koi8_u,
        .macintosh => &data.macintosh,
        .windows874 => &data.windows_874,
        .windows1250 => &data.windows_1250,
        .windows1251 => &data.windows_1251,
        .windows1252 => &data.windows_1252,
        .windows1253 => &data.windows_1253,
        .windows1254 => &data.windows_1254,
        .windows1255 => &data.windows_1255,
        .windows1256 => &data.windows_1256,
        .windows1257 => &data.windows_1257,
        .windows1258 => &data.windows_1258,
        .x_mac_cyrillic => &data.x_mac_cyrillic,
        else => unreachable,
    };
}

/// https://encoding.spec.whatwg.org/#index-gb18030-ranges-code-point
pub fn gb18030RangeCodePoint(position: u32) ?u21 {
    if ((position > 39419 and position < 189000) or position > 1237575) return null;
    if (position == 7457) return 0xE7C7;

    const ranges = &data.gb18030_ranges;
    var low: usize = 0;
    var high: usize = ranges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (ranges[mid][0] <= position) low = mid + 1 else high = mid;
    }
    const range = ranges[low - 1];
    return @intCast(range[1] + position - range[0]);
}

/// Returns the first pointer for a code point, or null.
/// https://encoding.spec.whatwg.org/#index-pointer
pub fn pointer(index: []const u21, cp: u21) ?usize {
    return std.mem.indexOfScalar(u21, index, cp);
}

/// Finds a gb18030 four-byte pointer for a scalar value.
/// https://encoding.spec.whatwg.org/#index-gb18030-ranges-pointer
pub fn gb18030RangePointer(cp: u21) u32 {
    if (cp == 0xE7C7) return 7457;
    const ranges = &data.gb18030_ranges;
    var low: usize = 0;
    var high: usize = ranges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (ranges[mid][1] <= cp) low = mid + 1 else high = mid;
    }
    const range = ranges[low - 1];
    return range[0] + cp - range[1];
}

/// Excludes the duplicate JIS entries specified for Shift_JIS encoding.
/// https://encoding.spec.whatwg.org/#index-shift_jis-pointer
pub fn shiftJisPointer(cp: u21) ?usize {
    if (pointer(jis0208[0..8272], cp)) |found| return found;
    return 8836 + (pointer(jis0208[8836..], cp) orelse return null);
}

/// Applies Big5's excluded entries and last-pointer rules.
/// https://encoding.spec.whatwg.org/#index-big5-pointer
pub fn big5Pointer(cp: u21) ?usize {
    const start = (0xA1 - 0x81) * 157;
    const index = big5[start..];
    const found = switch (cp) {
        0x2550, 0x255E, 0x2561, 0x256A, 0x5341, 0x5345 => std.mem.lastIndexOfScalar(u21, index, cp),
        else => pointer(index, cp),
    } orelse return null;
    return start + found;
}
