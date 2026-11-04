const std = @import("std");
const icu = @import("icu4z");
const encoding = @import("../../encoding/encoding.zig");
const host = @import("host.zig");
const ErrorAdapter = @import("ErrorAdapter.zig");

pub const DomainParseOpts = struct {
    be_strict: bool = false,
    adapter: ?ErrorAdapter = null,
};

/// Parses a domain using the URL Standard's IDNA options.
/// https://url.spec.whatwg.org/#concept-domain-to-ascii
pub fn parse(allocator: std.mem.Allocator, input: []const u21, options: DomainParseOpts) ![]u8 {
    const utf8 = try encoding.utf8Encode(allocator, input);
    defer allocator.free(utf8);
    const is_ascii = for (utf8) |byte| {
        if (!std.ascii.isAscii(byte)) break false;
    } else true;

    const strict = try toAscii(allocator, utf8, true);
    const strict_failed = strict.errors.any();
    if (strict_failed) ErrorAdapter.report(options.adapter, .DomainToAscii);

    if (options.be_strict) {
        if (!strict_failed) return strict.text;
        strict.deinit(allocator);
        return error.DomainToAscii;
    }
    defer strict.deinit(allocator);

    const result = if (is_ascii) try std.ascii.allocLowerString(allocator, utf8) else result: {
        const converted = try toAscii(allocator, utf8, false);
        if (converted.errors.any()) {
            converted.deinit(allocator);
            return error.DomainToAscii;
        }
        break :result converted.text;
    };
    errdefer allocator.free(result);
    if (result.len == 0) return error.DomainToAscii;
    for (result) |byte| {
        if (byte <= 0x20 or byte == 0x7f or byte == '%' or host.isForbiddenCodePoint(byte)) {
            ErrorAdapter.report(options.adapter, .DomainInvalidCodePoint);
            return error.DomainInvalidCodePoint;
        }
    }
    return result;
}

// Runs ICU ToASCII and ignores errors for checks disabled by beStrict.
fn toAscii(allocator: std.mem.Allocator, text: []const u8, be_strict: bool) !icu.Idna.Result {
    const c = icu.raw;
    var options: u32 = c.UIDNA_CHECK_BIDI | c.UIDNA_CHECK_CONTEXTJ | c.UIDNA_NONTRANSITIONAL_TO_ASCII;
    if (be_strict) options |= c.UIDNA_USE_STD3_RULES;
    const idna = try icu.Idna.init(options);
    defer idna.deinit();
    var result = try idna.nameToAscii(allocator, text);
    if (!be_strict) {
        result.errors.leading_hyphen = false;
        result.errors.trailing_hyphen = false;
        result.errors.hyphen_3_4 = false;
        result.errors.empty_label = false;
        result.errors.label_too_long = false;
        result.errors.domain_name_too_long = false;
    }
    return result;
}

test "network url domain: parse ASCII and Unicode domains" {
    const allocator = std.testing.allocator;
    const domain = try parse(allocator, &.{ 'E', 'X', '.', 'o', 'r', 'g' }, .{});
    defer allocator.free(domain);
    try std.testing.expectEqualStrings("ex.org", domain);
    const unicode = try parse(allocator, &.{ 'b', 0xfc, 'c', 'h', 'e', 'r', '.', 'd', 'e' }, .{});
    defer allocator.free(unicode);
    try std.testing.expectEqualStrings("xn--bcher-kva.de", unicode);
    try std.testing.expectError(error.DomainInvalidCodePoint, parse(allocator, &.{ 'a', '#', 'b' }, .{}));
    try std.testing.expectError(error.DomainToAscii, parse(allocator, &.{0xFFFD}, .{}));
}
