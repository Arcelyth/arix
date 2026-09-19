//! Provides lookup helpers for the encoding index tables generated from
//! `indexes.json`. These helpers are used by the encoding decoders to map
//! encoding-specific indexes or pointers to Unicode code points.
const Encoding = @import("encoding.zig").Encoding;
const data = @import("encoding_indexes");

pub const big5 = &data.big5;
pub const euc_kr = &data.euc_kr;
pub const gb18030 = &data.gb18030;
pub const jis0208 = &data.jis0208;
pub const jis0212 = &data.jis0212;

/// https://encoding.spec.whatwg.org/#index-code-point
pub fn codePoint(index: []const u21, pointer: usize) ?u21 {
    if (pointer >= index.len or index[pointer] == 0) return null;
    return index[pointer];
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
pub fn gb18030RangeCodePoint(pointer: u32) ?u21 {
    if ((pointer > 39419 and pointer < 189000) or pointer > 1237575) return null;
    if (pointer == 7457) return 0xE7C7;

    const ranges = &data.gb18030_ranges;
    var low: usize = 0;
    var high: usize = ranges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (ranges[mid][0] <= pointer) low = mid + 1 else high = mid;
    }
    const range = ranges[low - 1];
    return @intCast(range[1] + pointer - range[0]);
}
