//! This is an implementation of encoding sniff algorithm.
//! https://html.spec.whatwg.org/multipage/parsing.html#encoding-sniffing-algorithm
const std = @import("std");
const Encoding = @import("encoding.zig").Encoding;
const enc_map = @import("encoding.zig").enc_map;
const Attr = @import("attr.zig").Attr;
const AttrName = @import("attr.zig").AttrName;
const attr_name_map = @import("attr.zig").attr_name_map;
const get_attr = @import("attr.zig").get_attr;
const ascii = @import("ascii");

pub const Confidence = enum(u1) {
    Certain,
    Tentative,
};

pub fn prescan(input: []const u8) ?Encoding {
    const l = @min(input.len, 1024);
    var i: usize = 0;
    while (i < l) {
        const c = input[i];
        if (c != 0x3C) { // '<'
            i += 1;
            continue;
        }

        if (i + 1 >= l) break;
        const c1 = input[i + 1];

        // <!-- comment -->
        if (c1 == 0x21 and i + 3 < l and input[i + 2] == 0x2D and input[i + 3] == 0x2D) {
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
                    if (enc_res) |enc| return normPrescanEncoding(enc);
                    i += 2;
                    break;
                }
                i += 1;
            }
            continue;
        }

        // <meta ...>
        if (std.ascii.toLower(c1) == 'm' and
            i + 5 < l and
            std.ascii.toLower(input[i + 2]) == 'e' and
            std.ascii.toLower(input[i + 3]) == 't' and
            std.ascii.toLower(input[i + 4]) == 'a' and
            ascii.isHtmlSpace(input[i + 5]))
        {
            i += 6;
            var got_pragma = false;
            var enc_from_charset_attr = false;
            var enc_from_content_attr = false;
            var charset: ?Encoding = null;

            while (true) {
                const attr_res, const next_i = get_attr(input, &i, l);
                i = next_i;
                const attr = attr_res orelse break;

                const attr_name = attr_name_map.get(attr.name) orelse continue;
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
            if (charset) |ch| {
                if ((enc_from_charset_attr) or (enc_from_content_attr and got_pragma)) {
                    return normPrescanEncoding(ch);
                }
            }
            continue;
        }

        i += 1;
        while (i < l and input[i] != 0x3E) : (i += 1) {}
        if (i < l and input[i] == 0x3E) i += 1;
    }
    return null;
}

pub fn normPrescanEncoding(enc: Encoding) ?Encoding {
    return switch (enc) {
        .utf16le, .utf16be => .utf8,
        .user_defined => .windows1252,
        else => enc,
    };
}

/// https://encoding.spec.whatwg.org/#bom-sniff
pub fn getBomEncoding(input: []const u8) ?Encoding {
    const input_len = input.len;
    if (input_len >= 3 and input[0] == 0xEF and input[1] == 0xBB and input[2] == 0xBF) return .utf8;
    if (input_len >= 2 and input[0] == 0xFF and input[1] == 0xFE) return .utf16le;
    if (input_len >= 2 and input[0] == 0xFE and input[1] == 0xFF) return .utf16be;
    return null;
}

pub fn normLabel(
    buf: []u8,
    label: []const u8,
) ?[]const u8 {
    const cleaned = std.mem.trim(u8, label, " \t\r\n");
    if (cleaned.len == 0) return null;

    if (cleaned.len > buf.len) return null;
    for (cleaned, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }

    return buf[0..cleaned.len];
}

pub fn nameToEncoding(label: []const u8) ?Encoding {
    var buf: [64]u8 = undefined;
    const l = normLabel(&buf, label) orelse return null;
    if (l.len == 0) return null;

    return enc_map.get(l);
}

pub fn extractXmlDeclEncoding(str: []const u8) ?Encoding {
    var i: usize = 0;
    while (i + 7 < str.len) : (i += 1) {
        if (std.ascii.toLower(str[i]) == 'e' and
            std.ascii.toLower(str[i + 1]) == 'n' and
            std.ascii.toLower(str[i + 2]) == 'c' and
            std.ascii.toLower(str[i + 3]) == 'o' and
            std.ascii.toLower(str[i + 4]) == 'd' and
            std.ascii.toLower(str[i + 5]) == 'i' and
            std.ascii.toLower(str[i + 6]) == 'n' and
            std.ascii.toLower(str[i + 7]) == 'g')
        {
            var j = i + 8;
            while (j < str.len and ascii.isHtmlSpace(str[j])) : (j += 1) {}
            if (j >= str.len or str[j] != '=') {
                i += 8;
                continue;
            }

            j += 1;
            while (j < str.len and ascii.isHtmlSpace(str[j])) : (j += 1) {}
            if (j >= str.len) return null;

            if (str[j] == '"' or str[j] == '\'') {
                const quote = str[j];
                j += 1;
                const start = j;
                while (j < str.len and str[j] != quote) : (j += 1) {}
                if (j < str.len) return nameToEncoding(str[start..j]);
                return null;
            }
            const start = j;
            while (j < str.len and !ascii.isHtmlSpace(str[j]) and str[j] != '?') {
                j += 1;
            }
            return nameToEncoding(str[start..j]);
        }
    }
    return null;
}

/// https://html.spec.whatwg.org/#extracting-character-encodings-from-meta-elements
pub fn extractFromMeta(str: []const u8) ?Encoding {
    var i: usize = 0;

    while (i + 7 < str.len) : (i += 1) {
        // match "charset"
        if (!(std.ascii.toLower(str[i]) == 'c' and
            std.ascii.toLower(str[i + 1]) == 'h' and
            std.ascii.toLower(str[i + 2]) == 'a' and
            std.ascii.toLower(str[i + 3]) == 'r' and
            std.ascii.toLower(str[i + 4]) == 's' and
            std.ascii.toLower(str[i + 5]) == 'e' and
            std.ascii.toLower(str[i + 6]) == 't')) continue;

        var j = i + 7;

        // skip whitespace
        while (j < str.len and ascii.isHtmlSpace(str[j])) : (j += 1) {}

        if (j >= str.len or str[j] != '=') {
            continue;
        }

        j += 1;

        // skip whitespace after '='
        while (j < str.len and ascii.isHtmlSpace(str[j])) : (j += 1) {}

        if (j >= str.len) return null;

        // quoted value
        if (str[j] == '"' or str[j] == '\'') {
            const quote = str[j];
            j += 1;

            const start = j;
            while (j < str.len and str[j] != quote) : (j += 1) {}

            if (j >= str.len) return null;

            return nameToEncoding(str[start..j]);
        }

        // unquoted value
        const start = j;
        while (j < str.len and !ascii.isHtmlSpace(str[j]) and str[j] != ';') : (j += 1) {}

        return nameToEncoding(str[start..j]);
    }

    return null;
}

pub const EncodingOptions = struct {
    override_encoding: ?[]const u8,
    transport_encoding: ?[]const u8,
    parent_encoding: ?[]const u8,
    likely_encoding: ?[]const u8,
    default_encoding: ?[]const u8,
    same_origin_with_parent: bool,
};

pub fn encodingSniff(input: []const u8, opt: EncodingOptions) struct { Encoding, Confidence } {
    // BOM
    var enc = getBomEncoding(input);
    if (enc) |res| return .{ res, .Certain };

    // User override
    if (opt.override_encoding) |over| {
        const over_enc = nameToEncoding(over);
        if (over_enc) |res| return .{ res, .Certain };
    }

    // Transport layer
    if (opt.transport_encoding) |tran| {
        const tran_enc = nameToEncoding(tran);
        if (tran_enc) |res| return .{ res, .Certain };
    }

    // Prescan
    enc = prescan(input);
    if (enc) |pre_enc| return .{ pre_enc, .Tentative };

    // Same-origin parent
    if (opt.same_origin_with_parent) {
        if (opt.parent_encoding) |parent| {
            if (!ascii.isUtf16Family(parent)) {
                const parent_enc = nameToEncoding(parent);
                if (parent_enc) |res| return .{ res, .Tentative };
            }
        }
    }

    // Likely encoding
    if (opt.likely_encoding) |like_enc| {
        const likely_enc = nameToEncoding(like_enc);
        if (likely_enc) |res| return .{ res, .Tentative };
    }

    // Default
    if (opt.default_encoding) |def_enc| {
        const default_enc = nameToEncoding(def_enc);
        if (default_enc) |res| return .{ res, .Tentative };
    }

    return .{ .windows1252, .Tentative };
}
