const std = @import("std");
const encoding = @import("../html/encoding/encoding.zig");

pub fn determineFallbackEncoding(
    http_encoding: ?[]const u8,
    byte_stream: []const u8,
    env_encoding: ?[]const u8,
) encoding.Encoding {
    if (http_encoding) |encoding_label|
        if (encoding.enc_map.get(encoding_label)) |enc| return enc;

    const check_len = @min(byte_stream.len, 1024);
    const prefix = byte_stream[0..check_len];

    // Hex sequence: 40 63 68 61 72 73 65 74 20 22
    const marker = "@charset \"";

    if (std.mem.startsWith(u8, prefix, marker)) {
        var i: usize = marker.len;

        while (i < prefix.len) : (i += 1) {
            const c = prefix[i];

            // 22 3B
            if (c == '"') {
                if (i + 1 < prefix.len and prefix[i + 1] == ';') {
                    const label = prefix[marker.len..i];

                    if (encoding.enc_map.get(label)) |enc| {
                        if (enc == .utf16be or enc == .utf16le) {
                            return .utf8;
                        }
                        return enc;
                    }
                }
                break;
            }

            // XX*
            if ((c >= 0x01 and c <= 0x21) or (c >= 0x23 and c <= 0x7F))
                continue
            else
                break;
        }
    }

    if (env_encoding) |label|
        if (encoding.enc_map.get(label)) |enc| return enc;

    return .utf8;
}

test "css encode: determine fallback encoding from @charset" {
    const css =
        \\@charset "windows-1252";
        \\body { color: red; }
    ;

    const result = determineFallbackEncoding(null, css, null);

    try std.testing.expectEqual(
        .windows1252,
        result,
    );
}
