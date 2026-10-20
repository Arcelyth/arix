const Fallback = @This();
const std = @import("std");
const fc = @import("fontconfig_zig");
const hb = @import("harfbuzz_zig");
const Font = @import("Font.zig");
const utils = @import("utils.zig");

base: Font,
candidates: ?fc.FontSet = null,
initialized: bool = false,
fonts: std.ArrayList(Font) = .empty,

pub fn deinit(self: *Fallback, allocator: std.mem.Allocator) void {
    for (self.fonts.items) |font| font.deinit();
    self.fonts.deinit(allocator);
    if (self.candidates) |fonts| fonts.deinit();
}

/// Returns a font covering the whole grapheme, or the base font for .notdef.
pub fn forText(self: *Fallback, allocator: std.mem.Allocator, text: []const u8) !Font {
    if (supports(self.base, text)) return self.base;
    for (self.fonts.items) |font| if (supports(font, text)) return font;

    if (!self.initialized) {
        self.candidates = try self.sortedFonts(allocator);
        self.initialized = true;
    }
    const candidates = self.candidates orelse return self.base;

    for (0..candidates.len()) |i| {
        const descriptor = candidates.get(i).?;
        if (try utils.sameFace(descriptor, self.base.descriptor)) continue;
        const charset = try descriptor.getCharSet(fc.raw.FC_CHARSET, 0) orelse continue;
        var iterator = std.unicode.Utf8View.initUnchecked(text).iterator();
        const covered = while (iterator.nextCodepoint()) |codepoint| {
            if (requiresGlyph(codepoint) and !charset.contains(codepoint)) break false;
        } else true;
        if (!covered) continue;
        const font = Font.initWithDescriptor(descriptor, self.base.size) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => continue, // A stale cache entry or unusable face must not stop fallback.
        };

        if (!supports(font, text)) {
            font.deinit();
            continue;
        }
        errdefer font.deinit();
        try self.fonts.append(allocator, font);
        return font;
    }

    return self.base;
}

fn sortedFonts(self: Fallback, allocator: std.mem.Allocator) !?fc.FontSet {
    const config = try fc.Config.init();
    defer config.deinit();
    const query = try fc.Pattern.init();
    defer query.deinit();
    if (try self.base.descriptor.getString(fc.raw.FC_FAMILY, 0)) |name|
        try query.addString(allocator, fc.raw.FC_FAMILY, name);

    inline for (.{
        .{ fc.raw.FC_WEIGHT, fc.raw.FC_WEIGHT_REGULAR },
        .{ fc.raw.FC_WIDTH, fc.raw.FC_WIDTH_NORMAL },
        .{ fc.raw.FC_SLANT, fc.raw.FC_SLANT_ROMAN },
    }) |property| try query.addInteger(property[0], try self.base.descriptor.getInteger(property[0], 0) orelse property[1]);

    try config.substitute(query, fc.raw.FcMatchPattern);
    query.defaultSubstitute();

    return config.sortFonts(query, false);
}

fn supports(font: Font, text: []const u8) bool {
    var iterator = std.unicode.Utf8View.initUnchecked(text).iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        if (requiresGlyph(codepoint) and font.native.getCharIndex(codepoint) == null) return false;
    }

    return true;
}

fn requiresGlyph(codepoint: u21) bool {
    // These affect shaping but do not require a standalone glyph.
    if (codepoint == 0x034f or (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        (codepoint >= 0xe0100 and codepoint <= 0xe01ef)) return false;

    return switch (hb.unicode.generalCategory(codepoint)) {
        hb.raw.HB_UNICODE_GENERAL_CATEGORY_CONTROL,
        hb.raw.HB_UNICODE_GENERAL_CATEGORY_FORMAT,
        hb.raw.HB_UNICODE_GENERAL_CATEGORY_LINE_SEPARATOR,
        hb.raw.HB_UNICODE_GENERAL_CATEGORY_PARAGRAPH_SEPARATOR,
        => false,
        else => true,
    };
}
