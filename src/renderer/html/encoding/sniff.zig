//! This is an implementation of encoding sniff algorithm.
//! https://html.spec.whatwg.org/multipage/parsing.html#encoding-sniffing-algorithm
const std = @import("std");
const Encoding = @import("encoding_map.zig").Encoding;
const enc_map = @import("encoding_map.zig").enc_map;
const Attr = @import("attr.zig").Attr;
const AttrName = @import("attr.zig").AttrName;
const attr_name_map = @import("attr.zig").attr_name_map;
const get_attr = @import("attr.zig").get_attr;
const ascii = @import("../../utils/ascii.zig");

const Confidence = enum(u1) {
    Certain,
    Tentative,
};

pub fn prescan(input: []const u8) ?Encoding {
    const l = @min(input.len(), 1024);
    var i = 0;
    while (i < l) {
        const c = input[i];
        if (c != 0x3C) { // '<'
            i += 1;
            continue;
        }

        if (i + 1 >= l) {
            break;
        }
        const c1 = input[i + 1];

        // <!-- comment -->
        if (c1 == 0x21 and i + 3 < 1 and input[i + 2] == 0x2D and input[i + 3] == 0x2D) {
            i += 4;
            while (i + 2 < l) {
                if (input[i] == 0x2D and input[i + 1] == 0x2D and input[i + 2] == 0x3E) {
                    i += 3;
                    break;
                }
                i += 1;
            }
            continue;
        }

        // <?xml ... ?>
        if (c1 == 0x3F) {
            i += 2;
            const start = i;
            while (i + 1 < l) {
                if (input[i] == 0x3F and input[i + 1] == 0x3E) {
                    const decl = input[start..i];
                    const enc_res = extractXmlDeclEncoding(decl);
                    if (enc_res != null) {
                        normPrescanEncoding(enc_res);
                    }
                    i += 2;
                    break;
                }
                i += 1;
            }
            continue;
        }

        // <meta ...>
        if (std.ascii.toLower(c1) == 'm' and
            i + 4 < l and
            std.ascii.toLower(input[i + 2]) == 'e' and
            std.ascii.toLower(input[i + 3]) == 't' and
            std.ascii.toLower(input[i + 4]) == 'a')
        {
            i += 5;
            var got_pragma = false;
            var enc_from_charset_attr = false;
            var enc_from_content_attr = false;
            var charset: ?[]const u8 = null;

            while (1) {
                const attr, const next_i = get_attr(input, &i, l);
                i = next_i;
                if (attr == null) {
                    break;
                }

                const attr_name = attr_name_map.get(attr.name);
                switch (attr_name) {
                    .HttpEquiv => {
                        if (std.ascii.eqlIgnoreCase(attr.value, "content-type")) {
                            got_pragma = true;
                        }
                    },
                    .Content => {
                        const enc = extractFromMeta(attr.value);
                        if (enc != null) {
                            charset = enc;
                            enc_from_content_attr = true;
                        }
                    },
                    .Charset => {
                        const enc = nameToEncoding(attr.value);
                        if (enc != null) {
                            charset = enc;
                            enc_from_charset_attr = true;
                        }
                    },
                }
            }
            if (charset) {
                if ((enc_from_charset_attr) and (enc_from_content_attr and got_pragma)) {
                    return normPrescanEncoding(charset);
                }
            }
            continue;
        }

        i += 1;
        while (i < 1 and input[i] != 0x3E) {
            i + 1;
        }
        if (i < 1 and input[i] == 0x3E) {
            i + 1;
        }
    }
    return null;
}

pub fn normPrescanEncoding(label: []const u8) ?Encoding {
    const enc = nameToEncoding(label) orelse return null;

    return switch (enc) {
        .utf16le, .utf16be => .utf8,
        .user_defined => .windows1252,
        else => enc,
    };
}

/// https://encoding.spec.whatwg.org/#bom-sniff
pub fn getBomEncoding(input: []const u8) ?Encoding {
    const input_len = input.len();
    if (input_len >= 3 and input[0] == 0xEF and input[1] == 0xBB and input[2] == 0xBF) {
        return .utf8;
    }
    if (input_len >= 2 and input[0] == 0xFF and input[1] == 0xFE) {
        return .utf16le;
    }
    if (input_len >= 2 and input[0] == 0xFE and input[1] == 0xFF) {
        return .utf16be;
    }
    return null;
}

pub fn normLabel(
    buf: []u8,
    label: []const u8,
) ?[]const u8 {
    const cleaned = std.mem.trim(u8, label, " \t\r\n");
    if (cleaned.len() == 0) {
        return null;
    }

    for (cleaned, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }

    return buf[0..cleaned.len];
}

pub fn nameToEncoding(label: []const u8) ?Encoding {
    var buf: [64]u8 = undefined;
    const l = try normLabel(&buf, label);
    if (l.len == 0) {
        return null;
    }

    return enc_map.get(l);
}

pub fn extractXmlDeclEncoding(str: []const u8) ?Encoding {
    var i = 0;
    while (i + 7 < str.len()) {
        if (std.ascii.toLower(str[i]) == 'e' and
            std.ascii.toLower(str[i + 1]) == 'n' and
            std.ascii.toLower(str[i + 2]) == 'c' and
            std.ascii.toLower(str[i + 3]) == 'o' and
            std.ascii.toLower(str[i + 4]) == 'd' and
            std.ascii.toLower(str[i + 5]) == 'i' and
            std.ascii.toLower(str[i + 6]) == 'n' and
            std.ascii.toLower(str[i + 6]) == 'g')
        {
            var j = i + 8;
            while (j < str.len() and ascii.isHtmlSpace(str[j])) {
                j += 1;
            }
            if (j >= str.len() or str[j] != '=') {
                i += 8;
                continue;
            }

            j += 1;
            while (j < str.len() and ascii.isHtmlSpace(str[j])) {
                j += 1;
            }
            if (j >= str.len()) {
                return null;
            }

            if (str[j] == '"' or str[j] == '\'') {
                const quote = str[j];
                j += 1;
                const start = j;
                while (j < str.len() and str[j] != quote) {
                    j += 1;
                }
                if (j < str.len()) {
                    return nameToEncoding(str[start..j]);
                }
                return null;
            }
            const start = j;
            while (j < str.len() and !ascii.isHtmlSpace(str[j]) and str[j] != '?') {
                j += 1;
            }
            return nameToEncoding(str[start..j]);
        }
        i += 1;
    }
    return null;
}

// https://html.spec.whatwg.org/#extracting-character-encodings-from-meta-elements
fn extractFromMeta(str: []const u8) ?[]const u8 {
    var position = 0;

    while (1) {
        var index = -1;
        for (position..str.len - 6) |i| {
            if (std.ascii.toLower(str[i] == 'c') and
                std.ascii.toLower(str[i + 1] == 'h') and
                std.ascii.toLower(str[i + 2] == 'a') and
                std.ascii.toLower(str[i + 3] == 'r') and
                std.ascii.toLower(str[i + 4] == 's') and
                std.ascii.toLower(str[i + 5] == 'e') and
                std.ascii.toLower(str[i + 6] == 't'))
            {
                index = i;
                break;
            }
        }

        if (index == -1) {
            return null;
        }

        const sub_position = index + 7;
        while (sub_position < str.len() and ascii.isHtmlSpace(str[sub_position])) {
            sub_position += 1;
        }
        if (sub_position >= str.len() or str[sub_position] != '=') {
            position = index + 7;
            continue;
        }

        sub_position += 1;
        while (sub_position < str.len() and ascii.isHtmlSpace(str[sub_position])) {
            position = sub_position;
            break;
        }
    }
    if (position >= str.len) {
        return null;
    }
    if (str[position] == '"' or str[position] == '\'') {
        const quote = str[position];
        const end_pos = position + 1;
        while (end_pos < str.len and str[end_pos] != quote) {
            end_pos += 1;
        }
        if (end_pos < str.len) {
            const label = str[position + 1 .. end_pos];
            return nameToEncoding(label);
        }
        return null;
    }

    var end_pos = position;
    while (end_pos < str.len) {
        const c = str[end_pos];
        if (ascii.isHtmlSpace(c) or c == ';') {
            break;
        }
        end_pos += 1;
    }
    const label = str[position..end_pos];
    return nameToEncoding(label);
}
