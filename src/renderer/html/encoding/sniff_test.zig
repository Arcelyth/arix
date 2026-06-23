const std = @import("std");
const normLabel = @import("sniff.zig").normLabel;
const nameToEncoding = @import("sniff.zig").nameToEncoding;
const encodingSniff = @import("sniff.zig").encodingSniff;
const Confidence = @import("sniff.zig").Confidence;
const EncodingOptions = @import("sniff.zig").EncodingOptions;
const extractXmlDeclEncoding = @import("sniff.zig").extractXmlDeclEncoding;
const extractFromMeta = @import("sniff.zig").extractFromMeta;
const normPrescanEncoding = @import("sniff.zig").normPrescanEncoding;
const getBomEncoding = @import("sniff.zig").getBomEncoding;
const prescan = @import("sniff.zig").prescan;

const Encoding = @import("encoding.zig").Encoding;

test "normLabel trims and lowercases" {
    var buf: [64]u8 = undefined;
    const got = normLabel(buf[0..], " \t UTF-8 \r\n");
    try std.testing.expect(got != null);
    try std.testing.expectEqualStrings("utf-8", got.?);
}

test "nameToEncoding maps aliases to canonical encoding" {
    const cases = [_]struct {
        label: []const u8,
        expected: Encoding,
    }{
        .{ .label = "utf-8", .expected = .utf8 },
        .{ .label = "UTF8", .expected = .utf8 },
        .{ .label = "unicode-1-1-utf-8", .expected = .utf8 },
        .{ .label = "cp866", .expected = .ibm866 },
        .{ .label = "iso-8859-1", .expected = .windows1252 },
        .{ .label = "windows-1252", .expected = .windows1252 },
        .{ .label = "gbk", .expected = .gbk },
        .{ .label = "gb18030", .expected = .gb18030 },
        .{ .label = "big5", .expected = .big5 },
        .{ .label = "shift_jis", .expected = .shift_jis },
        .{ .label = "euc-kr", .expected = .euckr },
        .{ .label = "x-user-defined", .expected = .user_defined },
        .{ .label = "utf-16le", .expected = .utf16le },
        .{ .label = "utf-16be", .expected = .utf16be },
    };

    for (cases) |case| {
        const got = nameToEncoding(case.label);
        try std.testing.expect(got != null);
        try std.testing.expectEqual(case.expected, got.?);
    }
}

test "nameToEncoding returns null for empty or unknown labels" {
    try std.testing.expect(nameToEncoding("") == null);
    try std.testing.expect(nameToEncoding("   ") == null);
    try std.testing.expect(nameToEncoding("not-a-real-encoding") == null);
}

test "getBomEncoding detects bom" {
    try std.testing.expectEqual(.utf8, getBomEncoding("\xEF\xBB\xBFhello").?);
    try std.testing.expectEqual(.utf16le, getBomEncoding("\xFF\xFEh\x00").?);
    try std.testing.expectEqual(.utf16be, getBomEncoding("\xFE\xFF\x00h").?);
    try std.testing.expect(getBomEncoding("hello") == null);
}

test "extractXmlDeclEncoding parses quoted and unquoted encoding" {
    try std.testing.expectEqual(
        .utf8,
        extractXmlDeclEncoding("version=\"1.0\" encoding=\"utf-8\"").?,
    );
    try std.testing.expectEqual(
        .utf16be,
        extractXmlDeclEncoding("version='1.0' encoding='utf-16be'").?,
    );
    try std.testing.expectEqual(
        .gbk,
        extractXmlDeclEncoding("encoding=gbk standalone=\"yes\"").?,
    );
}

test "extractFromMeta parses charset from content attribute" {
    const a = extractFromMeta("text/html; charset=utf-8");
    try std.testing.expect(a != null);
    try std.testing.expectEqual(.utf8, a.?);

    const b = extractFromMeta("text/html; charset=gbk");
    try std.testing.expect(b != null);
    try std.testing.expectEqual(.gbk, b.?);

    const c = extractFromMeta("text/html; charset='shift_jis'");
    try std.testing.expect(c != null);
    try std.testing.expectEqual(.shift_jis, c.?);
}

test "prescan finds meta charset" {
    try std.testing.expectEqual(
        .utf8,
        prescan("<meta charset=\"utf-8\">").?,
    );

    try std.testing.expectEqual(
        .gbk,
        prescan("<!-- comment --><meta charset=\"gbk\">").?,
    );

    try std.testing.expectEqual(
        .windows1252,
        prescan("<meta charset=\"x-user-defined\">").?,
    );
}

test "prescan normalizes xml decl encodings" {
    try std.testing.expectEqual(
        .utf8,
        prescan("<?xml version=\"1.0\" encoding=\"utf-16be\"?>").?,
    );
}

test "prescan ignores meta beyond first 1024 bytes" {
    var buf: [1100]u8 = undefined;
    @memset(buf[0..1020], 'a');
    const tail = "<meta charset=\"utf-8\">";
    @memcpy(buf[1020 .. 1020 + tail.len], tail);

    try std.testing.expect(prescan(buf[0..]) == null);
}

fn makeOptions() EncodingOptions {
    return .{
        .override_encoding = null,
        .transport_encoding = null,
        .parent_encoding = null,
        .likely_encoding = null,
        .default_encoding = null,
        .same_origin_with_parent = false,
    };
}

fn expectSniff(res: struct { Encoding, Confidence }, enc: Encoding, conf: Confidence) !void {
    try std.testing.expectEqual(enc, res[0]);
    try std.testing.expectEqual(conf, res[1]);
}

test "encodingSniff BOM wins over everything" {
    var opt = makeOptions();
    opt.override_encoding = "gbk";
    opt.transport_encoding = "windows-1251";
    opt.default_encoding = "windows-1252";

    const res = encodingSniff("\xEF\xBB\xBF<meta charset=\"utf-8\">", opt);
    try expectSniff(res, .utf8, .Certain);
}

test "encodingSniff override beats transport and prescan" {
    var opt = makeOptions();
    opt.override_encoding = "windows-1251";
    opt.transport_encoding = "gbk";

    const res = encodingSniff("<meta charset=\"utf-8\">", opt);
    try expectSniff(res, .windows1251, .Certain);
}

test "encodingSniff transport beats prescan" {
    var opt = makeOptions();
    opt.transport_encoding = "gbk";

    const res = encodingSniff("<meta charset=\"utf-8\">", opt);
    try expectSniff(res, .gbk, .Certain);
}

test "encodingSniff prescan beats parent" {
    var opt = makeOptions();
    opt.same_origin_with_parent = true;
    opt.parent_encoding = "gbk";

    const res = encodingSniff("<meta charset=\"utf-8\">", opt);
    try expectSniff(res, .utf8, .Tentative);
}

test "encodingSniff parent is used when no better signal" {
    var opt = makeOptions();
    opt.same_origin_with_parent = true;
    opt.parent_encoding = "gbk";

    const res = encodingSniff("<html><head></head><body></body></html>", opt);
    try expectSniff(res, .gbk, .Tentative);
}

test "encodingSniff likely and default fallback" {
    var opt = makeOptions();
    opt.likely_encoding = "shift_jis";
    opt.default_encoding = "windows-1252";

    const res = encodingSniff("<html><head></head><body></body></html>", opt);
    try expectSniff(res, .shift_jis, .Tentative);
}

test "encodingSniff uses default when nothing else is present" {
    var opt = makeOptions();
    opt.default_encoding = "windows-1252";

    const res = encodingSniff("<html><head></head><body></body></html>", opt);
    try expectSniff(res, .windows1252, .Tentative);
}
