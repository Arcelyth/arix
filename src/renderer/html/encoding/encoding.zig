const std = @import("std");

pub const Encoding = enum {
    utf8,
    ibm866,
    iso88592,
    iso88593,
    iso88594,
    iso88595,
    iso88596,
    iso88597,
    iso88598,
    iso88598_i,
    iso885910,
    iso885913,
    iso885914,
    iso885915,
    iso885916,
    koi8r,
    koi8u,
    macintosh,
    windows1250,
    windows1251,
    windows1252,
    windows1253,
    windows1254,
    windows1255,
    windows1256,
    windows1257,
    windows1258,
    gbk,
    gb18030,
    big5,
    eucjp,
    iso2022jp,
    shift_jis,
    euckr,
    replacement,
    utf16le,
    utf16be,
    user_defined,
    windows874,
    x_mac_cyrillic,
};

/// https://encoding.spec.whatwg.org/#names-and-labels
const enc_map = std.StaticStringMap(Encoding).initComptime(.{
    // UTF-8
    .{ "unicode-1-1-utf-8", .utf8 },
    .{ "unicode11utf8", .utf8 },
    .{ "unicode20utf8", .utf8 },
    .{ "utf-8", .utf8 },
    .{ "utf8", .utf8 },
    .{ "x-unicode20utf8", .utf8 },

    // Legacy single-byte encodings

    // IBM866
    .{ "866", .ibm866 },
    .{ "cp866", .ibm866 },
    .{ "csibm866", .ibm866 },
    .{ "ibm866", .ibm866 },

    // ISO-8859-2
    .{ "csisolatin2", .iso88592 },
    .{ "iso-8859-2", .iso88592 },
    .{ "iso-ir-101", .iso88592 },
    .{ "iso8859-2", .iso88592 },
    .{ "iso88592", .iso88592 },
    .{ "iso_8859-2", .iso88592 },
    .{ "iso_8859-2:1987", .iso88592 },
    .{ "l2", .iso88592 },
    .{ "latin2", .iso88592 },

    // ISO-8859-3
    .{ "csisolatin3", .iso88593 },
    .{ "iso-8859-3", .iso88593 },
    .{ "iso-ir-109", .iso88593 },
    .{ "iso8859-3", .iso88593 },
    .{ "iso88593", .iso88593 },
    .{ "iso_8859-3", .iso88593 },
    .{ "iso_8859-3:1988", .iso88593 },
    .{ "l3", .iso88593 },
    .{ "latin3", .iso88593 },

    // ISO-8859-4
    .{ "csisolatin4", .iso88594 },
    .{ "iso-8859-4", .iso88594 },
    .{ "iso-ir-110", .iso88594 },
    .{ "iso8859-4", .iso88594 },
    .{ "iso88594", .iso88594 },
    .{ "iso_8859-4", .iso88594 },
    .{ "iso_8859-4:1988", .iso88594 },
    .{ "l4", .iso88594 },
    .{ "latin4", .iso88594 },

    // ISO-8859-5
    .{ "csisolatincyrillic", .iso88595 },
    .{ "cyrillic", .iso88595 },
    .{ "iso-8859-5", .iso88595 },
    .{ "iso-ir-144", .iso88595 },
    .{ "iso8859-5", .iso88595 },
    .{ "iso88595", .iso88595 },
    .{ "iso_8859-5", .iso88595 },
    .{ "iso_8859-5:1988", .iso88595 },

    // ISO-8859-6
    .{ "arabic", .iso88596 },
    .{ "asmo-708", .iso88596 },
    .{ "csiso88596e", .iso88596 },
    .{ "csiso88596i", .iso88596 },
    .{ "csisolatinarabic", .iso88596 },
    .{ "ecma-114", .iso88596 },
    .{ "iso-8859-6", .iso88596 },
    .{ "iso-8859-6-e", .iso88596 },
    .{ "iso-8859-6-i", .iso88596 },
    .{ "iso-ir-127", .iso88596 },
    .{ "iso8859-6", .iso88596 },
    .{ "iso88596", .iso88596 },
    .{ "iso_8859-6", .iso88596 },
    .{ "iso_8859-6:1987", .iso88596 },

    // ISO-8859-7
    .{ "csisolatingreek", .iso88597 },
    .{ "ecma-118", .iso88597 },
    .{ "elot_928", .iso88597 },
    .{ "greek", .iso88597 },
    .{ "greek8", .iso88597 },
    .{ "iso-8859-7", .iso88597 },
    .{ "iso-ir-126", .iso88597 },
    .{ "iso8859-7", .iso88597 },
    .{ "iso88597", .iso88597 },
    .{ "iso_8859-7", .iso88597 },
    .{ "iso_8859-7:1987", .iso88597 },
    .{ "sun_eu_greek", .iso88597 },

    // ISO-8859-8
    .{ "csiso88598e", .iso88598 },
    .{ "csisolatinhebrew", .iso88598 },
    .{ "hebrew", .iso88598 },
    .{ "iso-8859-8", .iso88598 },
    .{ "iso-8859-8-e", .iso88598 },
    .{ "iso-ir-138", .iso88598 },
    .{ "iso8859-8", .iso88598 },
    .{ "iso88598", .iso88598 },
    .{ "iso_8859-8", .iso88598 },
    .{ "iso_8859-8:1988", .iso88598 },
    .{ "visual", .iso88598 },

    // ISO-8859-8-I
    .{ "csiso88598i", .iso88598_i },
    .{ "iso-8859-8-i", .iso88598_i },
    .{ "logical", .iso88598_i },

    // ISO-8859-10
    .{ "csisolatin6", .iso885910 },
    .{ "iso-8859-10", .iso885910 },
    .{ "iso-ir-157", .iso885910 },
    .{ "iso8859-10", .iso885910 },
    .{ "iso885910", .iso885910 },
    .{ "l6", .iso885910 },
    .{ "latin6", .iso885910 },

    // ISO-8859-13
    .{ "iso-8859-13", .iso885913 },
    .{ "iso8859-13", .iso885913 },
    .{ "iso885913", .iso885913 },

    // ISO-8859-14
    .{ "iso-8859-14", .iso885914 },
    .{ "iso8859-14", .iso885914 },
    .{ "iso885914", .iso885914 },

    // ISO-8859-15
    .{ "csisolatin9", .iso885915 },
    .{ "iso-8859-15", .iso885915 },
    .{ "iso8859-15", .iso885915 },
    .{ "iso885915", .iso885915 },
    .{ "iso_8859-15", .iso885915 },
    .{ "l9", .iso885915 },

    // ISO-8859-16
    .{ "iso-8859-16", .iso885916 },

    // KOI8
    .{ "cskoi8r", .koi8r },
    .{ "koi", .koi8r },
    .{ "koi8", .koi8r },
    .{ "koi8-r", .koi8r },
    .{ "koi8_r", .koi8r },

    .{ "koi8-ru", .koi8u },
    .{ "koi8-u", .koi8u },

    // Mac
    .{ "csmacintosh", .macintosh },
    .{ "mac", .macintosh },
    .{ "macintosh", .macintosh },
    .{ "x-mac-roman", .macintosh },

    // Windows-874
    .{ "dos-874", .windows874 },
    .{ "iso-8859-11", .windows874 },
    .{ "iso8859-11", .windows874 },
    .{ "iso885911", .windows874 },
    .{ "tis-620", .windows874 },
    .{ "windows-874", .windows874 },

    // Windows-1250
    .{ "cp1250", .windows1250 },
    .{ "windows-1250", .windows1250 },
    .{ "x-cp1250", .windows1250 },

    // Windows-1251
    .{ "cp1251", .windows1251 },
    .{ "windows-1251", .windows1251 },
    .{ "x-cp1251", .windows1251 },

    // Windows-1252
    .{ "ansi_x3.4-1968", .windows1252 },
    .{ "ascii", .windows1252 },
    .{ "cp1252", .windows1252 },
    .{ "cp819", .windows1252 },
    .{ "csisolatin1", .windows1252 },
    .{ "ibm819", .windows1252 },
    .{ "iso-8859-1", .windows1252 },
    .{ "iso-ir-100", .windows1252 },
    .{ "iso8859-1", .windows1252 },
    .{ "iso88591", .windows1252 },
    .{ "iso_8859-1", .windows1252 },
    .{ "iso_8859-1:1987", .windows1252 },
    .{ "l1", .windows1252 },
    .{ "latin1", .windows1252 },
    .{ "us-ascii", .windows1252 },
    .{ "windows-1252", .windows1252 },
    .{ "x-cp1252", .windows1252 },

    // Windows-1253
    .{ "cp1253", .windows1253 },
    .{ "windows-1253", .windows1253 },
    .{ "x-cp1253", .windows1253 },

    // Windows-1254
    .{ "cp1254", .windows1254 },
    .{ "csisolatin5", .windows1254 },
    .{ "iso-8859-9", .windows1254 },
    .{ "iso-ir-148", .windows1254 },
    .{ "iso8859-9", .windows1254 },
    .{ "iso88599", .windows1254 },
    .{ "iso_8859-9", .windows1254 },
    .{ "iso_8859-9:1989", .windows1254 },
    .{ "l5", .windows1254 },
    .{ "latin5", .windows1254 },
    .{ "windows-1254", .windows1254 },
    .{ "x-cp1254", .windows1254 },

    // Windows-1255
    .{ "cp1255", .windows1255 },
    .{ "windows-1255", .windows1255 },
    .{ "x-cp1255", .windows1255 },

    // Windows-1256
    .{ "cp1256", .windows1256 },
    .{ "windows-1256", .windows1256 },
    .{ "x-cp1256", .windows1256 },

    // Windows-1257
    .{ "cp1257", .windows1257 },
    .{ "windows-1257", .windows1257 },
    .{ "x-cp1257", .windows1257 },

    // Windows-1258
    .{ "cp1258", .windows1258 },
    .{ "windows-1258", .windows1258 },
    .{ "x-cp1258", .windows1258 },

    // x-mac-cyrillic
    .{ "x-mac-cyrillic", .x_mac_cyrillic },
    .{ "x-mac-ukrainian", .x_mac_cyrillic },

    // Legacy multi-byte Chinese (simplified)
    .{ "chinese", .gbk },
    .{ "csgb2312", .gbk },
    .{ "csiso58gb231280", .gbk },
    .{ "gb2312", .gbk },
    .{ "gb_2312", .gbk },
    .{ "gb_2312-80", .gbk },
    .{ "gbk", .gbk },
    .{ "iso-ir-58", .gbk },
    .{ "x-gbk", .gbk },

    .{ "gb18030", .gb18030 },

    // Legacy multi-byte Chinese (traditional)
    .{ "big5", .big5 },
    .{ "big5-hkscs", .big5 },
    .{ "cn-big5", .big5 },
    .{ "csbig5", .big5 },
    .{ "x-x-big5", .big5 },

    // Legacy multi-byte Japanese
    .{ "cseucpkdfmtjapanese", .eucjp },
    .{ "euc-jp", .eucjp },
    .{ "x-euc-jp", .eucjp },

    .{ "csiso2022jp", .iso2022jp },
    .{ "iso-2022-jp", .iso2022jp },

    .{ "csshiftjis", .shift_jis },
    .{ "ms932", .shift_jis },
    .{ "ms_kanji", .shift_jis },
    .{ "shift-jis", .shift_jis },
    .{ "shift_jis", .shift_jis },
    .{ "sjis", .shift_jis },
    .{ "windows-31j", .shift_jis },
    .{ "x-sjis", .shift_jis },

    // Legacy multi-byte Korean
    .{ "cseuckr", .euckr },
    .{ "csksc56011987", .euckr },
    .{ "euc-kr", .euckr },
    .{ "iso-ir-149", .euckr },
    .{ "korean", .euckr },
    .{ "ks_c_5601-1987", .euckr },
    .{ "ks_c_5601-1989", .euckr },
    .{ "ksc5601", .euckr },
    .{ "ksc_5601", .euckr },
    .{ "windows-949", .euckr },

    // Legacy miscellaneous
    .{ "csiso2022kr", .replacement },
    .{ "hz-gb-2312", .replacement },
    .{ "iso-2022-cn", .replacement },
    .{ "iso-2022-cn-ext", .replacement },
    .{ "iso-2022-kr", .replacement },
    .{ "replacement", .replacement },

    .{ "unicodefffe", .utf16be },
    .{ "utf-16be", .utf16be },

    .{ "csunicode", .utf16le },
    .{ "iso-10646-ucs-2", .utf16le },
    .{ "ucs-2", .utf16le },
    .{ "unicode", .utf16le },
    .{ "unicodefeff", .utf16le },
    .{ "utf-16", .utf16le },
    .{ "utf-16le", .utf16le },

    .{ "x-user-defined", .user_defined },
});

pub fn encodingToString(encoding: Encoding) []const u8 {
    return switch (encoding) {
        // UTF-8
        .utf8 => "UTF-8",

        // Legacy single-byte encodings
        .ibm866 => "IBM866",
        .iso88592 => "ISO-8859-2",
        .iso88593 => "ISO-8859-3",
        .iso88594 => "ISO-8859-4",
        .iso88595 => "ISO-8859-5",
        .iso88596 => "ISO-8859-6",
        .iso88597 => "ISO-8859-7",
        .iso88598 => "ISO-8859-8",
        .iso88598_i => "ISO-8859-8-I",
        .iso885910 => "ISO-8859-10",
        .iso885913 => "ISO-8859-13",
        .iso885914 => "ISO-8859-14",
        .iso885915 => "ISO-8859-15",
        .iso885916 => "ISO-8859-16",
        .koi8r => "KOI8-R",
        .koi8u => "KOI8-U",
        .macintosh => "macintosh",
        .windows874 => "windows-874",
        .windows1250 => "windows-1250",
        .windows1251 => "windows-1251",
        .windows1252 => "windows-1252",
        .windows1253 => "windows-1253",
        .windows1254 => "windows-1254",
        .windows1255 => "windows-1255",
        .windows1256 => "windows-1256",
        .windows1257 => "windows-1257",
        .windows1258 => "windows-1258",
        .x_mac_cyrillic => "x-mac-cyrillic",

        // Legacy multi-byte Chinese (simplified)
        .gbk => "GBK",
        .gb18030 => "gb18030",

        // Legacy multi-byte Chinese (traditional)
        .big5 => "Big5",

        // Legacy multi-byte Japanese
        .eucjp => "EUC-JP",
        .iso2022jp => "ISO-2022-JP",
        .shift_jis => "Shift_JIS",

        // Legacy multi-byte Korean
        .euckr => "EUC-KR",

        // Legacy miscellaneous
        .replacement => "replacement",
        .utf16be => "UTF-16BE",
        .utf16le => "UTF-16LE",
        .user_defined => "x-user-defined",
    };
}
